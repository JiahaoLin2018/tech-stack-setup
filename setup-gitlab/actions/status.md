# action: status — 查看 GitLab 状态

## 步骤

### 步骤 1：测试 SSH 连通性

```bash
ssh [AUTH_OPTS] -o ConnectTimeout=10 -p <SSH_PORT> <SSH_USER>@<HOST> "echo SSH连接成功"
```

### 步骤 2：远程查看容器状态

```bash
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "docker ps --filter 'name=tech-gitlab' --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
```

### 步骤 3：远程查看 GitLab 内部服务状态

```bash
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "docker exec tech-gitlab gitlab-ctl status 2>/dev/null || echo '容器未运行或尚未就绪'"
```

输出汇总时将访问地址改为 `http://<HOST>:<GITLAB_HTTP_PORT>`。
