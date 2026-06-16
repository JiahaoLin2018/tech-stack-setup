# action: verify — 验证 Harbor 服务

---

## 步骤

### 步骤 1：测试 SSH 连通性

```bash
ssh [AUTH_OPTS] -o ConnectTimeout=10 -p <SSH_PORT> <SSH_USER>@<HOST> "echo SSH连接成功"
```

### 步骤 2：远程检查 Harbor 服务状态

```bash
REMOTE_HARBOR_DIR="/opt/tech-stack/harbor/harbor"
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "cd $REMOTE_HARBOR_DIR 2>/dev/null && docker compose ps || echo '未找到安装目录'"
```

### 步骤 3：远程测试 Harbor HTTP 访问

```bash
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://localhost:8880/ 2>/dev/null"
```

### 步骤 4：从本地测试远程 Harbor 可访问性

```bash
HARBOR_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://<HOST>/" 2>/dev/null)
echo "从本地访问远程 Harbor：http://<HOST>/ → $HARBOR_HTTP_CODE"

REGISTRY_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://<HOST>/v2/" 2>/dev/null)
echo "Registry API：http://<HOST>/v2/ → $REGISTRY_CODE（期望 401）"
```

输出汇总结果，指出 Harbor 的实际访问地址（`http://<HOST>` 或远程 harbor.yml 中的 hostname）。
