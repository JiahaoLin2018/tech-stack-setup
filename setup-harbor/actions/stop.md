# action: stop — 停止 Harbor

Harbor 通过其安装目录中的 docker compose.yml 管理服务生命周期。

---

## 步骤

### 步骤 1：测试 SSH 连通性

```bash
ssh [AUTH_OPTS] -o ConnectTimeout=10 -p <SSH_PORT> <SSH_USER>@<HOST> "echo SSH连接成功"
```

失败则报告错误并终止。

### 步骤 2：远程停止 Harbor

```bash
REMOTE_HARBOR_DIR="/opt/tech-stack/harbor/harbor"
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "cd $REMOTE_HARBOR_DIR && docker compose stop && echo 'Harbor 已停止'"
```

若远程 harbor 目录不存在，告知用户 Harbor 可能未安装或安装在其他路径。

---

## 恢复服务

```bash
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "cd /opt/tech-stack/harbor/harbor && docker compose start"
```

---

## Docker 服务重启后的 Harbor 恢复

> **重要**：Harbor 官方安装器生成的容器**未设置 `restart: unless-stopped`**，执行 `systemctl restart docker` 后容器不会自动恢复，需手动启动。

**问题现象**：
- `harbor-core` 状态 `Exited`
- `harbor-jobservice` 状态 `Restarting`，日志显示 `dial tcp: lookup core: no such host`
- nginx 未启动，端口 80 无监听

**恢复命令**：

```bash
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "cd /opt/tech-stack/harbor/harbor && docker compose start"
```

启动后等待 15-30 秒，验证：

```bash
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "curl -s -o /dev/null -w '%{http_code}' http://localhost/api/v2.0/ping"
# 期望输出：200
```
