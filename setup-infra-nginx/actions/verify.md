# action: verify — 验证 infra-nginx

## 步骤

```bash
# 健康检查
SSH_CMD "curl -sf http://localhost/health"

# TCP 透传端口（带空格精确匹配，避免误命中 :22220/:80820 等）
SSH_CMD "netstat -tlnp | grep -E ':2222 |:8082 '"

# 检查 nginx 配置语法
SSH_CMD "docker exec tech-infra-nginx nginx -t"
```

## 预期正常输出示例

```
{"status":"UP"}

tcp  0  0 0.0.0.0:2222  0.0.0.0:*  LISTEN
tcp  0  0 0.0.0.0:8082  0.0.0.0:*  LISTEN

nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

## 完整验证（DNS 配置后）

```bash
# HTTP 反代验证（需 DNS 已更新；upstream 未部署的域名会返回 502 属正常）
SSH_CMD "curl -sI http://gitlab.renew.com | head -1"
SSH_CMD "curl -sI http://harbor.renew.com | head -1"
SSH_CMD "curl -sI http://grafana-nonprod-ui.renew.com | head -1"
SSH_CMD "curl -sI http://apollo-config-fat.renew.com | head -1"
```

期望：upstream 已就绪 → `HTTP/1.1 200` 或 `HTTP/1.1 302`；upstream 未就绪 → `HTTP/1.1 502`
