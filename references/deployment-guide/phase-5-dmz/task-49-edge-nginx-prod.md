# Task 49 — 生产边缘网关部署

> 部署生产公网入口（DMZ 物理孤岛）。对应 architecture-blueprint.md 第五部分阶段五 5-1。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-41（K3s prod）已完成 |
| 公网 IP | 需要独立公网 IP（与 task-35 nonprod 不同 IP） |
| 机房 | 生产 DMZ 独立机房（物理孤岛） |
| SSL 证书 | 生产证书 `fullchain.pem` + `privkey.pem` |

## 架构约束

- B 类域级共用，DMZ 双实例物理隔离
- 仅支持 HTTPS（HTTP 自动 301 重定向）
- 后端 K3s `k3s-prod.renew.com:8083`
- host 网络模式
- 与非生产 edge-nginx（task-35）物理隔离 / 独立证书 / 独立机房

## 关键 .env 配置

| 变量 | 值 |
|------|---|
| `K3S_PROD_HOST` | `k3s-prod.renew.com`（prod 实例后端 K3s） |
| `K3S_PROD_PORT` | `8083` |
| `WHITELIST_IPS` | 可选 |
| `SSL_PROD_CERT` | `/opt/tech-stack/edge-nginx-prod/ssl/fullchain.pem`（生产证书） |
| `SSL_PROD_KEY` | `/opt/tech-stack/edge-nginx-prod/ssl/privkey.pem` |

> 容器名 / 部署目录由 `--env prod` 参数决定（`tech-edge-nginx-prod` / `/opt/tech-stack/edge-nginx-prod/`），不在 .env 中维护。

## 部署命令

```bash
/setup-edge-nginx start --host <EDGE_PROD_IP> --env prod --user <USER> --password <PASS>
/setup-edge-nginx verify --host <EDGE_PROD_IP> --env prod --user <USER> --password <PASS>
```

## 验证标准

- [ ] 容器运行：`docker ps --filter name=tech-edge-nginx-prod` 状态为 `Up`
- [ ] HTTPS 生产证书有效（CA 颁发，非自签名）：`echo | openssl s_client -connect <EDGE_PROD_IP>:443 | openssl x509 -noout -dates -issuer`
- [ ] `*.prod.web.renew.com` / `*.prod.api.renew.com` 公网 DNS 已解析到本节点公网 IP
- [ ] HTTP 自动 301 → HTTPS：`curl -I http://demo.prod.web.renew.com/` 返回 301
- [ ] 后端 K3s 可达：`curl -I http://k3s-prod.renew.com:8083`
- [ ] 健康检查：`curl http://<EDGE_PROD_IP>:8888/health` 返回 `OK`
- [ ] nginx 配置语法正确：`docker exec tech-edge-nginx-prod nginx -t`
- [ ] 安全头已生效（HSTS / X-Frame-Options / X-Content-Type-Options）

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 1 GB | 1 核 | 50 GB |

## 安全加固

- 必须启用 HTTPS + 限流 + 安全头
- 强烈建议接入 WAF
- 关键路径（admin / api 敏感接口）配置 IP 白名单
- 公网入口仅 :80（301）和 :443，其余端口防火墙关闭

## 注意事项

- 必须独立公网 IP（与 task-35 nonprod 不同）
- 生产证书须由 CA 颁发（Let's Encrypt 或商业证书）
- 部署后必须做完整压测（限流阈值是否合理）
- 健康检查端口 :8888 与 OTel Collector :8888 同号，禁止与 OTel Collector 同机部署

## 访问控制路由管理

生产关键路径（admin / 敏感 API）必须通过 `add-route` 配置 IP 白名单：

```bash
# 关键路径 IP 白名单
/setup-edge-nginx add-route --env prod \
  --domain admin.prod.web.renew.com \
  --mode whitelist \
  --ips "<办公网CIDR>,<VPN出口IP>"
```

## 后续步骤

- task-50（上线验证）
