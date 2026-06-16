# action: logs — 查看 Harbor 日志

---

## 步骤

### 步骤 1：测试 SSH 连通性

```bash
ssh [AUTH_OPTS] -o ConnectTimeout=10 -p <SSH_PORT> <SSH_USER>@<HOST> "echo SSH连接成功"
```

### 步骤 2：远程查看 Harbor 日志

```bash
REMOTE_HARBOR_DIR="/opt/tech-stack/harbor/harbor"
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "cd $REMOTE_HARBOR_DIR 2>/dev/null && docker compose logs --tail=100 || echo '未找到 Harbor 安装目录'"
```

注意：远程模式下无法实时流式输出日志。若需实时日志，提示用户直接 SSH 登录：

```
如需实时查看远程 Harbor 日志，请直接 SSH 登录：
  ssh -p <SSH_PORT> <SSH_USER>@<HOST>
  cd /opt/tech-stack/harbor/harbor
  docker compose logs -f --tail=50
```
