# Task 35 — 非生产边缘网关部署（可选）

> 为非生产环境提供公网访问入口。对应 architecture-blueprint.md 第五部分阶段三 3-12。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-27（K3s nonprod）已完成 |
| 公网 IP | 需要独立公网 IP（非生产 DMZ 机房） |
| SSL 证书 | `fullchain.pem` + `privkey.pem` 已上传至 `${DEPLOY_DIR}/ssl/` |
| 公网 DNS | `*.{dev\|sit\|fat\|uat}.{web\|api}.renew.com` 已解析到本节点公网 IP（可选） |

## 架构约束

- B 类域级共用，DMZ 双实例物理隔离（与 prod task-49 物理隔离）
- 仅支持 HTTPS（HTTP 自动 301 重定向）
- 后端 K3s `k3s-nonprod.renew.com:8083`
- host 网络模式
- :8888 健康检查（与 OTel Collector 同号，避免同机部署）

## 关键 .env 配置

| 变量 | 值 |
|------|---|
| `K3S_NONPROD_HOST` | `k3s-nonprod.renew.com`（nonprod 实例后端 K3s） |
| `K3S_NONPROD_PORT` | `8083` |
| `WHITELIST_IPS` | 可选，IP 白名单（CIDR / IP，逗号分隔） |
| `SSL_NONPROD_CERT` | `/opt/tech-stack/edge-nginx-nonprod/ssl/fullchain.pem` |
| `SSL_NONPROD_KEY` | `/opt/tech-stack/edge-nginx-nonprod/ssl/privkey.pem` |

> 容器名 / 部署目录由 `--env nonprod` 参数决定（`tech-edge-nginx-nonprod` / `/opt/tech-stack/edge-nginx-nonprod/`），不在 .env 中维护。

## 部署命令

```bash
/setup-edge-nginx start --host <EDGE_NONPROD_IP> --env nonprod --user <USER> --password <PASS>
/setup-edge-nginx verify --host <EDGE_NONPROD_IP> --env nonprod --user <USER> --password <PASS>
```

## 验证标准

- [ ] 容器运行：`docker ps --filter name=tech-edge-nginx-nonprod` 状态为 `Up`
- [ ] HTTPS 证书有效：`curl -k -I https://demo.fat.web.renew.com/` 返回 200（或 502 后端不可达）
- [ ] HTTP 301 重定向：`curl -I http://demo.fat.web.renew.com/` 返回 301 → HTTPS
- [ ] 后端 K3s 可达：`curl -I http://k3s-nonprod.renew.com:8083`
- [ ] 健康检查：`curl http://<EDGE_NONPROD_IP>:8888/health` 返回 `OK`
- [ ] nginx 配置语法正确：`docker exec tech-edge-nginx-nonprod nginx -t`
- [ ] 安全头已配置：`curl -k -I https://demo.fat.web.renew.com/` 包含 HSTS / X-Frame-Options / X-Content-Type-Options

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 1 GB | 1 核 | 20 GB |

## 可选说明

本 task 为可选，主要服务于：
- 外部测试人员公网访问非生产环境
- 第三方对接联调（webhook 回调等）

如无公网访问需求，可跳过本 task。

## 注意事项

- 必须独立公网 IP（与 task-49 prod 不同 IP）
- IP 白名单建议：仅放行测试人员办公网 / VPN 出口 IP
- 测试证书可用 Let's Encrypt 或自签名
- 健康检查端口 :8888 与 OTel Collector :8888 同号，禁止与 OTel Collector 同机部署

## 访问控制路由管理

部署后通过 `add-route` action 添加单域名路由（公开 / IP 白名单两种模式）：

```bash
# 公开访问（通常已被通配路由覆盖，无需额外配置）
/setup-edge-nginx add-route --env nonprod --domain api.v2.fat.web.renew.com --mode public

# IP 白名单（仅指定 IP / CIDR 可访问）
/setup-edge-nginx add-route --env nonprod \
  --domain internal.fat.api.renew.com \
  --mode whitelist \
  --ips "192.168.1.0/24,10.0.0.0/8"
```

## 后续步骤

- 公网 DNS 配置 `*.{dev|sit|fat|uat}.{web|api}.renew.com` → `<EDGE_NONPROD_PUBLIC_IP>`
- 任意时机可继续 task-36~48（生产建设）
