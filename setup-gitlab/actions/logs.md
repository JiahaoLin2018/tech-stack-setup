# action: logs — 查看 GitLab 日志

## 步骤

### 步骤 1：测试 SSH 连通性

```bash
ssh [AUTH_OPTS] -o ConnectTimeout=10 -p <SSH_PORT> <SSH_USER>@<HOST> "echo SSH连接成功"
```

### 步骤 2：远程查看容器日志

```bash
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "docker logs --tail=100 tech-gitlab"
```

注意：远程模式下无法实时流式输出日志（-f 标志不适用于 SSH 管道）。若需实时日志，建议直接 SSH 登录远程服务器后执行 `docker logs -f tech-gitlab`。

提示用户：

```
如需实时查看远程日志，请直接 SSH 登录：
  ssh -p <SSH_PORT> <SSH_USER>@<HOST>
  docker logs -f tech-gitlab
```
