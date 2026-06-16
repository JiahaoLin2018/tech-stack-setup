# action: status — 查看 infra-nginx 状态

## 步骤

```bash
SSH_CMD "docker ps -a --filter name=tech-infra-nginx --format 'table {{.Status}}\t{{.Names}}'"
# 端口正则带前导冒号 + 末尾空格，精确匹配 LISTEN 行末端口字段，避免误命中 :8080/:80820 等
SSH_CMD "netstat -tlnp | grep -E ':80 |:2222 |:8082 '"
```

## 预期正常输出示例

```
STATUS              NAMES
Up 2 hours (healthy) tech-infra-nginx

tcp  0  0 0.0.0.0:80     0.0.0.0:*  LISTEN  1234/nginx
tcp  0  0 0.0.0.0:2222   0.0.0.0:*  LISTEN  1234/nginx
tcp  0  0 0.0.0.0:8082   0.0.0.0:*  LISTEN  1234/nginx
```

> **注意**：使用 host 网络模式，端口直接由 nginx 进程绑定，不经过 docker-proxy。
