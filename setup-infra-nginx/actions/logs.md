# action: logs — 查看 infra-nginx 日志

## 步骤

```bash
# 最近 50 行日志
SSH_CMD "docker logs --tail 50 tech-infra-nginx"

# 实时日志
SSH_CMD "docker logs -f tech-infra-nginx"
```

## 日志文件位置

```bash
# 访问日志
SSH_CMD "tail -50 /opt/tech-stack/infra-nginx/logs/access.log"

# 错误日志
SSH_CMD "tail -50 /opt/tech-stack/infra-nginx/logs/error.log"

# Stream 日志（TCP 透传）
SSH_CMD "tail -50 /opt/tech-stack/infra-nginx/logs/stream.log"
```
