# action: start — 启动 Nexus

> Nexus Repository OSS 3 启动较慢，首次初始化约需 60-90 秒。
> 健康检查 start_period 为 120 秒，请耐心等待。

## 步骤

> **文件上传约束**：上传 docker-compose.yml 等含 `${VAR}` 变量引用的文件时，必须使用文件复制方式（`scp` 或 `sftp.put()`），禁止使用 Python 字符串写入（会导致 `${VAR}` 被吞掉变为空值）。详见 `references/deployment-principles.md` 前置准备第 6 节。

### 前置检查：全局唯一服务拒绝 --env 参数

```bash
# 本 skill 为 C 类全局唯一服务，不接受 --env 参数
if [ -n "${ENV}" ]; then
  echo "ERROR: setup-nexus is a global-unique service and does not accept --env"
  exit 1
fi
```

若用户传入了 `--env` 参数，立即报错退出，不继续执行后续步骤。

### 步骤 1：检查本地 SSH 工具

```bash
# 密码模式
which sshpass > /dev/null 2>&1 || echo "MISSING_SSHPASS"
# 密钥模式
ls ${SSH_KEY_PATH} 2>/dev/null || echo "MISSING_KEY"
```

### 步骤 2：测试 SSH 连接

```bash
# 密码模式
sshpass -p "${SSH_PASSWORD}" ssh -o StrictHostKeyChecking=no -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} "echo OK"
# 密钥模式
ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} "echo OK"
```

### 步骤 3：检查远程 Docker（未安装则自动安装）

```bash
SSH_CMD "docker info > /dev/null 2>&1 || (curl -fsSL https://get.docker.com | sh && systemctl enable --now docker)"
```

### 步骤 4：上传 references/ 到远程目录

```bash
# 密码模式
sshpass -p "${SSH_PASSWORD}" scp -r -P ${SSH_PORT:-22} \
  ${CLAUDE_SKILL_DIR}/references/. ${SSH_USER:-root}@${HOST}:/opt/tech-stack/nexus/

# 密钥模式
scp -i ${SSH_KEY_PATH} -r -P ${SSH_PORT:-22} \
  ${CLAUDE_SKILL_DIR}/references/. ${SSH_USER:-root}@${HOST}:/opt/tech-stack/nexus/
```

### 步骤 5：准备远程数据目录

```bash
SSH_CMD "mkdir -p /opt/tech-stack/nexus/data && chown 200:200 /opt/tech-stack/nexus/data && chmod 755 /opt/tech-stack/nexus/data"
SSH_CMD "ls /opt/tech-stack/nexus/.env 2>/dev/null || cp /opt/tech-stack/nexus/.env.example /opt/tech-stack/nexus/.env"
```

### 步骤 6：远程启动容器

```bash
SSH_CMD "cd /opt/tech-stack/nexus && docker compose up -d"
```

### 步骤 7：远程健康检查（最多 150 秒）

```bash
SSH_CMD "for i in \$(seq 1 10); do
  STATUS=\$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${NEXUS_PORT:-8081}/service/rest/v1/status 2>/dev/null)
  [ \"\$STATUS\" = '200' ] && echo 'Nexus: 就绪' && break
  echo \"启动中...\$i/10 HTTP:\${STATUS:-无响应}\"; sleep 15
done"
```

### 步骤 8：获取远程初始密码

```bash
SSH_CMD "docker exec tech-nexus cat /nexus-data/admin.password 2>/dev/null || echo '密码文件不存在，可能已完成首次登录配置'"
```

### 步骤 9：展示连接信息

```
Nexus 已在 ${HOST} 启动

UI 界面：  http://nexus.renew.com（via infra-nginx:80 → 宿主机:8081 → 容器:8081）
账号：     admin
初始密码：  <上一步输出>

Maven settings.xml 配置：
  Mirror URL：http://nexus.renew.com/repository/maven-public/

若域名无法解析，请确认 dnsmasq 已部署并在本机配置 DNS 指向 dnsmasq 服务器。
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

## 备注

- <部署过程中的特殊配置或踩坑记录>
```

报告文件路径：`<project_root>/env/<service>.md`（如 `env/mysql.md`、`env/redis.md`）
