# Action: start

启动 Redis 服务（支持本地和远程两种部署模式）。

## 命令格式

```
/setup-redis start [--env <env>] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]
```

## 步骤

> **文件上传约束**：上传 docker-compose.yml 等含 `${VAR}` 变量引用的文件时，必须使用文件复制方式（`scp` 或 `sftp.put()`），禁止使用 Python 字符串写入（会导致 `${VAR}` 被吞掉变为空值）。详见 `references/deployment-principles.md` 前置准备第 6 节。

1. **解析 --env 参数**：
   - 提取 ENV（默认 `dev`）
   - 校验合法值：必须为 `dev|sit|fat|uat|prod`，否则立即报错退出：
     ```
     ❌ --env 参数非法：${ENV}。合法值：dev|sit|fat|uat|prod
     ```
   - 根据 ENV 确定部署目录 `DEPLOY_DIR=/opt/tech-stack/redis-${ENV}` 和容器名 `CONTAINER=tech-redis-${ENV}`

2. **检查本地 SSH 工具**：
   - 密码认证：检查 `sshpass` 是否已安装（`which sshpass`），未安装则提示：`brew install sshpass` (Mac) / `apt install sshpass` (Linux)
   - Key 认证：检查 key 文件存在且权限正确（`chmod 600 <key>`）

3. **测试 SSH 连通性**：
   ```bash
   # 密码认证
   sshpass -p "$PASS" ssh -p $SSH_PORT -o StrictHostKeyChecking=no -o ConnectTimeout=5 $USER@$HOST "echo OK"
   # Key 认证
   ssh -i "$KEY" -p $SSH_PORT -o StrictHostKeyChecking=no -o ConnectTimeout=5 $USER@$HOST "echo OK"
   ```

4. **检查/安装远程 Docker**：
   ```bash
   ssh ... "docker info > /dev/null 2>&1 || (curl -fsSL https://get.docker.com | sh && systemctl enable docker && systemctl start docker)"
   ```

5. **上传配置文件**：
   ```bash
   ssh ... "mkdir -p ${DEPLOY_DIR}"
   scp ... -r ${CLAUDE_SKILL_DIR}/references/. $USER@$HOST:${DEPLOY_DIR}/
   ```

6. **检查/初始化远程 .env 并强制对齐 ENV 行**：
   ```bash
   ssh ... "test -f ${DEPLOY_DIR}/.env || {
     cp ${DEPLOY_DIR}/.env.example ${DEPLOY_DIR}/.env
     sed -i 's|^ENV=.*|ENV=${ENV}|' ${DEPLOY_DIR}/.env
     echo '⚠️  .env 已生成，请编辑修改 CHANGE_ME_* 密码后重试'
     exit 1
   }
   # 已存在 .env 时也强制对齐 ENV 行（防止 .env 中 ENV 与 --env 参数不一致导致容器名错位）
   sed -i 's|^ENV=.*|ENV=${ENV}|' ${DEPLOY_DIR}/.env
   # 检查占位符
   grep -q 'CHANGE_ME' ${DEPLOY_DIR}/.env && {
     echo '⚠️  .env 中仍含 CHANGE_ME_* 占位符，请先修改为实际密码'
     exit 1
   }"
   ```

7. **初始化 ACL 文件并注入密码**：
   ```bash
   # 仅首次部署时生成 data/users.acl（已存在则保留运行时修改）
   ssh ... "set -e; mkdir -p ${DEPLOY_DIR}/data; \
     if [ ! -f ${DEPLOY_DIR}/data/users.acl ]; then \
       set -a; . ${DEPLOY_DIR}/.env; set +a; \
       sed -e \"s|__REDIS_PASSWORD__|\${REDIS_PASSWORD}|\" \
           -e \"s|__REDIS_APP_PASSWORD__|\${REDIS_APP_PASSWORD}|\" \
           -e \"s|__REDIS_EXPORTER_PASSWORD__|\${REDIS_EXPORTER_PASSWORD}|\" \
           ${DEPLOY_DIR}/conf/users.acl > ${DEPLOY_DIR}/data/users.acl; \
       chmod 600 ${DEPLOY_DIR}/data/users.acl; \
     fi"
   ```
   `redis.conf` 配置 `aclfile /data/users.acl`；模板中的 `__REDIS_*_PASSWORD__` 占位符在首次部署时由 `.env` 实际密码替换，写入可写卷 `data/users.acl`。后续 ACL 变更通过 `ACL SETUSER` 命令在线修改，由 Redis 持久化回该文件，模板不再覆盖。

8. **校验三处 Exporter 密码一致**：
   ```bash
   ssh ... "set -e; set -a; . ${DEPLOY_DIR}/.env; set +a; \
     ACL_PWD=\$(awk '/^user exporter/{for(i=1;i<=NF;i++){if(\$i ~ /^>/){print substr(\$i,2)}}}' ${DEPLOY_DIR}/data/users.acl); \
     [ \"\${ACL_PWD}\" = \"\${REDIS_EXPORTER_PASSWORD}\" ] || { echo '❌ exporter 密码不一致：data/users.acl 与 .env 不匹配'; exit 1; }; \
     echo '✅ Exporter 密码一致性校验通过'"
   ```
   docker-compose 的 `redis-exporter` 容器通过 `${REDIS_EXPORTER_PASSWORD}` 注入，与 `.env` 同源，无需单独比对。

9. **远程启动**：
   ```bash
   ssh ... "cd ${DEPLOY_DIR} && docker compose up -d"
   ```

10. **等待健康检查**：
   ```bash
   ssh ... "docker inspect ${CONTAINER} --format='{{.State.Health.Status}}'"
   ```
   - 返回 `healthy` → 继续
   - 超时 → `ssh ... "docker logs ${CONTAINER} --tail 30"` 展示日志

11. **展示连接信息**：
   ```
   ✅ Redis 8.0（${ENV} 环境）已成功部署至远程服务器！

   连接信息（域名方式，推荐）：
     地址：redis-${ENV}.renew.com:${REDIS_PORT:-6379}
     密码：<请查看远程 .env>

   连接命令：
     redis-cli -h redis-${ENV}.renew.com -p ${REDIS_PORT:-6379} -a <password>

   注意：请确保 DNS hosts.lan 中已配置 redis-${ENV}.renew.com 指向 $HOST
   ```

---

## 部署报告输出

> 部署完成后，必须在项目 `env/` 目录下生成或更新该服务的部署报告文件 `env/<service>.md`。

报告模板：

```markdown
# <服务名称> — 部署报告

| 项目 | 值 |
|------|-----|
| 部署日期 | YYYY-MM-DD |
| 目标机器 | <IP> |
| 部署目录 | /opt/tech-stack/<service>/ |
| 容器名称 | <container_name> |
| 镜像 | <image:tag> |
| 版本 | <version> |

## 端口

| 端口 | 用途 |
|------|------|
| <port> | <description> |

## 账号密码

| 用户 | 密码 | 权限 | 允许来源 |
|------|------|------|---------|
| <user> | <password> | <permissions> | <access_scope> |

## 连接方式

| 方式 | 地址 |
|------|------|
| <client_type> | <connection_string> |

## 多环境部署说明

当前实例环境：`${ENV}`，域名：`redis-${ENV}.renew.com:6379`

> 每个环境（dev/sit/fat/uat/prod）为完全独立的物理实例，通过 `--env` 参数区分。
> 每个实例使用 DB 0（无需通过 Database Index 隔离，实例本身已完全隔离）。

## 备注

- <部署过程中的特殊配置或踩坑记录>
```

报告文件路径：`<project_root>/env/redis-${ENV}.md`（如 `env/redis-dev.md`、`env/redis-prod.md`）
