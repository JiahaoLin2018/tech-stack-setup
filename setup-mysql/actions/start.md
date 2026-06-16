# Action: start

启动 MySQL 服务（支持本地和远程两种部署模式）。

## 命令格式

```
/setup-mysql start [--env <env>] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]
```

## 步骤

> **文件上传约束**：上传 docker-compose.yml 等含 `${VAR}` 变量引用的文件时，必须使用文件复制方式（`scp` 或 `sftp.put()`），禁止使用 Python 字符串写入（会导致 `${VAR}` 被吞掉变为空值）。详见 `references/deployment-principles.md` 前置准备第 6 节。

1. **解析 --env 参数**：
   - 提取 ENV（默认 `dev`）
   - 校验合法值：必须为 `dev|sit|fat|uat|prod`，否则立即报错退出：
     ```
     ❌ --env 参数非法：${ENV}。合法值：dev|sit|fat|uat|prod
     ```
   - 根据 ENV 确定部署目录 `DEPLOY_DIR=/opt/tech-stack/mysql-${ENV}` 和容器名 `CONTAINER=tech-mysql-${ENV}`

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

6. **检查远程 .env**：
   ```bash
   ssh ... "test -f ${DEPLOY_DIR}/.env"
   ```
   - 不存在 → 提示用户：
     ```
     ssh $USER@$HOST "cp ${DEPLOY_DIR}/.env.example ${DEPLOY_DIR}/.env && nano ${DEPLOY_DIR}/.env"
     ```
     修改所有 CHANGE_ME_* 密码后重试（其中 ENV 已预设为 `${ENV}`）
   - 存在 → 检查占位符：
     ```bash
     ssh ... "grep -q 'CHANGE_ME' ${DEPLOY_DIR}/.env" && {
       echo "⚠️  远程 .env 中仍包含 CHANGE_ME_* 占位符，请先修改为实际密码"
       exit 1
     }
     ```

6b. **校验 Exporter 密码三处一致**（强制项，防止 exporter 启动失败）：
   ```bash
   ssh ... "
     ENV_PWD=\$(grep '^MYSQL_EXPORTER_PASSWORD=' ${DEPLOY_DIR}/.env | cut -d'=' -f2-)
     CNF_PWD=\$(grep '^password=' ${DEPLOY_DIR}/conf/exporter.my.cnf | cut -d'=' -f2-)
     SQL_PWD=\$(grep -oP \"IDENTIFIED BY '\\K[^']+\" ${DEPLOY_DIR}/init/01_create_app_user.sql)
     if [ \"\$ENV_PWD\" = \"\$CNF_PWD\" ] && [ \"\$ENV_PWD\" = \"\$SQL_PWD\" ]; then
       echo '✅ Exporter 密码三处一致'
     else
       echo '❌ Exporter 密码不一致，需同步 .env / conf/exporter.my.cnf / init/01_create_app_user.sql'
       exit 1
     fi
   "
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

9. **展示连接信息**：
   ```
   ✅ MySQL 8.4（${ENV} 环境）已成功部署至远程服务器！

   连接信息（域名方式，推荐）：
     地址：mysql-${ENV}.renew.com:${MYSQL_PORT:-3306}
     Root 用户：root / <请查看远程 .env>
     应用用户：${MYSQL_APP_USER:-appuser}

   连接命令：
     mysql -h mysql-${ENV}.renew.com -P ${MYSQL_PORT:-3306} -u root -p

   注意：请确保 DNS hosts.lan 中已配置 mysql-${ENV}.renew.com 指向 $HOST
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

当前实例环境：`${ENV}`，域名：`mysql-${ENV}.renew.com:3306`

> 每个环境（dev/sit/fat/uat/prod）为完全独立的物理实例，通过 `--env` 参数区分。
> 业务 DB 命名建议：`${ENV}_{业务域}`（如 `dev_order`、`prod_payment`）。

## 备注

- <部署过程中的特殊配置或踩坑记录>
```

报告文件路径：`<project_root>/env/mysql-${ENV}.md`（如 `env/mysql-dev.md`、`env/mysql-prod.md`）
