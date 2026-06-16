# Action: start

启动 RabbitMQ 服务（支持本地和远程两种部署模式）。

## 命令格式

```
/setup-rabbitmq start [--env <env>] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]
```

## 步骤

> **文件上传约束**：上传 docker-compose.yml 等含 `${VAR}` 变量引用的文件时，必须使用文件复制方式（`scp` 或 `sftp.put()`），禁止使用 Python 字符串写入（会导致 `${VAR}` 被吞掉变为空值）。详见 `references/deployment-principles.md` 前置准备第 6 节。

1. **解析 --env 参数**：
   - 提取 ENV（默认 `dev`）
   - 校验合法值：必须为 `dev|sit|fat|uat|prod`，否则立即报错退出：
     ```
     ❌ --env 参数非法：${ENV}。合法值：dev|sit|fat|uat|prod
     ```
   - 根据 ENV 确定部署目录 `DEPLOY_DIR=/opt/tech-stack/rabbitmq-${ENV}` 和容器名 `CONTAINER=tech-rabbitmq-${ENV}`

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

7. **远程启动**：
   ```bash
   ssh ... "cd ${DEPLOY_DIR} && docker compose up -d"
   ```

8. **等待健康检查**：
   ```bash
   ssh ... "docker inspect ${CONTAINER} --format='{{.State.Health.Status}}'"
   ```
   - 返回 `healthy` → 继续
   - 超时 → `ssh ... "docker logs ${CONTAINER} --tail 30"` 展示日志

9. **初始化 vhost**（可选，如需多应用 vhost 隔离）：
   ```bash
   ssh ... "docker exec ${CONTAINER} bash /init/01_init_env_vhosts.sh"
   ```
   - 在同一实例内为不同应用创建专属 vhost（非多环境隔离，实例已独立）

10. **展示连接信息**：
   ```
   ✅ RabbitMQ 4.0（${ENV} 环境）已成功部署至远程服务器！

   连接信息（域名方式，推荐）：
     AMQP 地址：rabbitmq-${ENV}.renew.com:${RABBITMQ_AMQP_PORT:-5672}
     Management UI：http://rabbitmq-${ENV}-ui.renew.com（infra-nginx 反代）
     Prometheus 指标：http://rabbitmq-${ENV}.renew.com:${RABBITMQ_PROMETHEUS_PORT:-15692}/metrics
     管理员账号：${RABBITMQ_USER:-admin}
     管理员密码：<请查看远程 .env>
     默认 vhost：/

   注意：请确保防火墙已开放端口 5672、15672（infra-nginx 反代可不直接暴露）和 15692（Prometheus 采集），
         并已在 DNS hosts.lan 中配置 rabbitmq-${ENV}.renew.com 指向 $HOST
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

当前实例环境：`${ENV}`，AMQP 域名：`rabbitmq-${ENV}.renew.com:5672`，UI：`http://rabbitmq-${ENV}-ui.renew.com`

> 每个环境（dev/sit/fat/uat/prod）为完全独立的物理实例，Spring Boot 使用默认 vhost `/` 即可。

## 备注

- <部署过程中的特殊配置或踩坑记录>
```

报告文件路径：`<project_root>/env/rabbitmq-${ENV}.md`（如 `env/rabbitmq-dev.md`、`env/rabbitmq-prod.md`）
