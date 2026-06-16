# Task 21 — DMZ Traefik 部署

- **状态**: ✅ 已完成
- **目标机器**: 192.168.82.97
- **Skill**: setup-traefik
- **前置依赖**: Task 20 (K3s 安装完成)

## 目标

在 97 机器部署 Traefik Ingress Controller，作为业务流量入口（DMZ 区），路由到 K3s Pod。

## 功能说明

| 功能 | 说明 |
|------|------|
| 业务流量入口 | 接收外部 HTTP/HTTPS 请求 |
| 路由转发 | `*.fat.api.renew.com` / `*.fat.web.renew.com` → K3s Pod |
| SSL 终止 | HTTPS 证书管理（可选） |
| IP 白名单 | 访问控制（可选） |

## 架构说明

```
Internet / 开发者机器
    │
    ▼
┌─────────────────────────────────────┐
│  97 机器 (DMZ)                       │
│  Traefik :80/:443                   │
│  - 业务域名入口                      │
│  - SSL 终止                          │
│  - 路由规则                          │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│  93 机器 (LAN)                       │
│  K3s Traefik :8083                  │
│  → K3s Pod                          │
└─────────────────────────────────────┘
```

## Skill 命令

```bash
/setup-traefik start --host 192.168.82.97 --user root --password foxconn.88
/setup-traefik verify --host 192.168.82.97 --user root --password foxconn.88
```

## 域名路由规则

| 域名模式 | 用途 | 路由目标 |
|---------|------|---------|
| `*.fat.api.renew.com` | 业务 API | K3s Gateway / Backend Pod |
| `*.fat.web.renew.com` | 业务前端 | K3s Frontend Pod |

## 验证清单

- [x] Traefik 容器运行正常
- [x] :80/:443 端口监听
- [x] 健康检查 `/ping` 返回 200
- [ ] 路由到 K3s 正常（需有应用部署后验证）

## 完成记录

- 开始时间: 2026-04-01 17:45
- 完成时间: 2026-04-01 17:50
- 备注: 使用 Python paramiko 部署成功，容器状态 healthy，端口 :80/:443/:8888 监听正常
