# action: stop — 停止 GitLab

## 步骤

### 步骤 1：测试 SSH 连通性

```bash
ssh [AUTH_OPTS] -o ConnectTimeout=10 -p <SSH_PORT> <SSH_USER>@<HOST> "echo SSH连接成功"
```

失败则报告错误并终止。

### 步骤 2：远程停止服务

```bash
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "cd /opt/tech-stack/gitlab && docker compose stop"
echo "远程 GitLab 已停止，数据目录保留于 /opt/tech-stack/gitlab/"
```

---

## 恢复服务

```bash
cd /opt/tech-stack/gitlab && docker compose start
```
