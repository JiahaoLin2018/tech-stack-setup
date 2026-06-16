# Traefik 部署信息

部署时间: 2026-04-01 17:50
部署机器: 192.168.82.97

## 端口

| 端口 | 用途 |
|------|------|
| :80 | HTTP 业务入口 |
| :443 | HTTPS 业务入口（证书配置后生效） |
| :8888 | 健康检查 /ping（内部） |

## 路由配置

- 动态配置目录: /opt/tech-stack/traefik/dynamic/
- 修改 routes.yml / middlewares.yml 后自动热更新，无需重启
- 转发目标: 192.168.82.93:8083 (K3s Traefik)

注意: K3s Traefik 使用 8083 端口（8080 被 Apollo Config 占用）

## 访问控制

- 公开域名: 不附加 Middleware，见 routes.yml prod-frontend 示例
- IP 白名单域名: 附加 ip-whitelist-internal，见 routes.yml fat-frontend 示例
- 白名单 IP 管理: /opt/tech-stack/traefik/dynamic/middlewares.yml

## 日志

访问日志: /opt/tech-stack/traefik/logs/access.log
错误日志: /opt/tech-stack/traefik/logs/traefik.log

## 验证结果

- [x] Traefik 容器运行正常 (traefik:v3.2, healthy)
- [x] :80/:443/:8888 端口监听正常
- [x] 健康检查 /ping 返回 OK
