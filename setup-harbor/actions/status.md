# action: status — 查看 Harbor 状态

---

## 步骤

### 步骤 1：测试 SSH 连通性

```bash
ssh [AUTH_OPTS] -o ConnectTimeout=10 -p <SSH_PORT> <SSH_USER>@<HOST> "echo SSH连接成功"
```

### 步骤 2：远程查看 Harbor 服务状态

```bash
REMOTE_HARBOR_DIR="/opt/tech-stack/harbor/harbor"
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "cd $REMOTE_HARBOR_DIR 2>/dev/null && docker compose ps || echo '未找到 Harbor 安装目录'"
```

输出汇总时将访问地址替换为 `http://<HOST>` 或远程 harbor.yml 中配置的 hostname。
