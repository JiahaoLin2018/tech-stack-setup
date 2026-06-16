---
name: setup-edge-nginx
description: 在公网边界部署 nginx 边缘网关，支持非生产/生产双实例。统一 HTTPS 访问，支持公开和 IP 白名单两种访问控制模式。非生产实例处理 dev/sit/fat/uat 公网流量，生产实例处理 prod 公网流量。
argument-hint: "[start|stop|status|verify|logs|add-route] [--env nonprod|prod] [--host <ip>] [--user <user>] [--password <pass>|--key <path>] [--domain <domain>] [--mode <public|whitelist>] [--ips <ip1,ip2,...>]"
disable-model-invocation: true
---

# setup-edge-nginx — AI 执行指令

> 本文件供 Claude Code 执行。面向人类的说明见 README.md。

## 文档职责

| 文件 | 职责 |
|------|------|
| SKILL.md | AI 执行指令（本文件） |
| README.md | 面向人类的部署指南 |
| actions/start.md | 部署启动步骤 |
| actions/stop.md | 停止服务步骤 |
| actions/status.md | 状态查询步骤 |
| actions/verify.md | 验证检查步骤 |
| actions/logs.md | 日志查看步骤 |
| actions/add-route.md | 添加路由步骤 |
| references/ | 配置文件模板 |

## 服务定位

**edge-nginx** 是部署在 DMZ 公网边界的 nginx 网关，职责：

1. **公网流量入口** — 接收来自公网的业务流量
2. **HTTPS 终止** — 统一 HTTPS 访问，HTTP 自动 301 重定向
3. **访问控制** — 支持公开和 IP 白名单两种模式
4. **安全防护** — TLS 1.2+、安全头、限流

### 与 infra-nginx 的区别

| 特性 | infra-nginx | edge-nginx |
|------|-------------|------------|
| 部署位置 | 内网 | DMZ 公网边界 |
| 端口 | 80 / 2222 / 8082 | 80（重定向） / 443（HTTPS） |
| 流量来源 | 内网开发者 | 公网用户 |
| HTTPS | 不终止 | 终止 SSL |
| 访问控制 | 无 | IP 白名单 / 公开 |

## --env 参数契约（B 类，域级共用+生产独立）

```
setup-edge-nginx --env <nonprod|prod>

默认值：nonprod
传错处理：报错退出（非法值退出）
```

DMZ 双实例物理隔离部署：`nonprod` 与 `prod` 拥有独立公网 IP、独立机房、独立 SSL 证书。建议生产部署时仍显式传入 `--env prod`，避免与非生产实例混淆。

| 配置项 | nonprod | prod |
|--------|---------|------|
| K3S 后端 | ${K3S_NONPROD_HOST}:${K3S_NONPROD_PORT} | ${K3S_PROD_HOST}:${K3S_PROD_PORT} |
| 容器名 | tech-edge-nginx-nonprod | tech-edge-nginx-prod |
| 部署目录 | /opt/tech-stack/edge-nginx-nonprod/ | /opt/tech-stack/edge-nginx-prod/ |
| 路由域名 | *.dev/sit/fat/uat.web/api.renew.com | *.prod.web/api.renew.com |

## 访问控制模式

| 模式 | 说明 | 配置方式 |
|------|------|---------|
| **公开** | 任意 IP 可访问 | 默认，通配路由 |
| **IP 白名单** | 仅指定 IP 可访问 | add-route --mode whitelist |

## Actions

| Action | 说明 |
|--------|------|
| start | 部署并启动 edge-nginx |
| stop | 停止服务 |
| status | 查询运行状态 |
| verify | 验证配置正确性 |
| logs | 查看日志 |
| add-route | 添加新路由（公开/白名单） |

## 执行流程

1. 解析 --env 参数，确定 nonprod 或 prod
2. 读取 .env 获取 K3S 地址
3. 渲染 nginx 配置（注入变量）
4. 上传配置文件和 SSL 证书
5. 启动容器
6. 验证 HTTPS 访问

## 前置条件

- [ ] K3s 集群已部署（nonprod 或 prod）
- [ ] SSL 证书已准备好（fullchain.pem + privkey.pem）
- [ ] 公网 DNS 已配置域名解析
- [ ] **部署方已确认公网业务域名**：`references/conf/nginx/conf.d/20-{env}-routes.conf` 中 `server_name` 正则的域名（如 `*.prod.web/api.renew.com`）为参考实现，部署时必须替换为部署方实际持有的公网主域名，并与 SSL 证书一致

## 使用示例

```bash
# 部署非生产实例
/setup-edge-nginx start --env nonprod --host 192.168.1.100

# 部署生产实例
/setup-edge-nginx start --env prod --host 10.0.1.100

# 添加白名单路由
/setup-edge-nginx add-route --env prod --domain admin.prod.web.renew.com --mode whitelist --ips "192.168.1.0/24,10.0.0.0/8"
```

## 注意事项

1. **SSL 证书必填** — 部署前必须上传证书到 ssl/ 目录
2. **HTTP 自动重定向** — 所有 HTTP 请求自动 301 到 HTTPS
3. **域名级访问控制** — 不同域名可配置不同访问模式
4. **配置渲染** — 使用 Python 脚本安全替换变量，禁止硬编码 IP

> 历史踩坑记录及解决方案详见 [pitfalls.md](references/pitfalls.md)，部署中遇到的新问题也请记录到该文件。
