# setup-edge-nginx — 公网边缘网关

在 DMZ 公网边界部署 nginx 边缘网关，作为业务流量的公网入口。

## 服务概述

| 项目 | 说明 |
|------|------|
| 服务名称 | edge-nginx |
| 版本 | nginx:1.27-alpine |
| 部署位置 | DMZ 公网边界节点 |
| 端口 | 80（HTTP→HTTPS 重定向）/ 443（HTTPS） |
| 部署方式 | Docker Compose |

## 核心功能

1. **公网流量入口** — 接收来自公网的业务流量
2. **HTTPS 终止** — 统一 HTTPS 访问，HTTP 自动 301 重定向
3. **访问控制** — 支持公开和 IP 白名单两种模式
4. **安全防护** — TLS 1.2+、安全头

## 双实例部署

edge-nginx 支持非生产和生产双实例部署：

| 环境 | --env 参数 | 处理域名 | 部署目录 |
|------|-----------|---------|---------|
| 非生产 | nonprod | *.dev/sit/fat/uat.web/api.renew.com | /opt/tech-stack/edge-nginx-nonprod/ |
| 生产 | prod | *.prod.web/api.renew.com | /opt/tech-stack/edge-nginx-prod/ |

## 访问控制模式

| 模式 | 说明 | 使用场景 |
|------|------|---------|
| **公开** | 任意 IP 可访问 | 对外公开的生产服务 |
| **IP 白名单** | 仅指定 IP 可访问 | 内部系统、管理后台 |

## 公网业务域名

`references/conf/nginx/conf.d/20-{env}-routes.conf` 中 `server_name` 正则使用的 `*.{env}.web/api.renew.com` 是**参考实现**。生产部署时部署方应根据实际持有的公网主域名调整：

| 项 | 调整方式 |
|---|---|
| nginx `server_name` 正则 | 编辑 `references/conf/nginx/conf.d/20-{env}-routes.conf`，将 `renew\.com` 替换为实际主域名（注意正则转义）|
| SSL 证书 | `fullchain.pem` 必须覆盖实际主域名（推荐 wildcard 或 SAN 证书）|
| 公网 DNS 解析 | A 记录指向 edge-nginx 公网 IP |
| 业务方调用方 | 前端 / 第三方对接 / 移动端配置同步更新 |

> **建议**：生产 / 测试使用不同的公网主域名（如生产 `*.api.{brand}.com`、测试 `*.{env}.{brand}-uat.com`），便于 SSL 证书、DNS 服务商、Cookie 边界、SEO 完全隔离。内部域名 `*.renew.com` 不受影响，仍由 dnsmasq 解析。

## 快速开始

### 1. 准备 SSL 证书

```bash
# 上传证书到目标服务器
scp fullchain.pem privkey.pem root@<dmz-ip>:/opt/tech-stack/edge-nginx-prod/ssl/
```

### 2. 配置环境变量

```bash
# 复制并编辑 .env
cp references/.env.example references/.env
# 编辑 K3S_NONPROD_HOST、K3S_PROD_HOST 等
```

### 3. 部署

```bash
# 非生产实例
/setup-edge-nginx start --env nonprod --host <dmz-ip>

# 生产实例
/setup-edge-nginx start --env prod --host <dmz-ip>
```

### 4. 验证

```bash
# 验证 HTTPS
curl -k https://<dmz-ip>/ -H "Host: demo.prod.web.renew.com"
```

## 添加白名单路由

```bash
/setup-edge-nginx add-route --env prod \
  --domain admin.prod.web.renew.com \
  --mode whitelist \
  --ips "192.168.1.0/24,10.0.0.0/8"
```

## 目录结构

```
setup-edge-nginx/
├── SKILL.md                 # AI 执行指令
├── README.md                # 本文件
├── install.sh               # 一键安装脚本
├── actions/                 # 操作步骤
│   ├── start.md
│   ├── stop.md
│   ├── status.md
│   ├── verify.md
│   ├── logs.md
│   └── add-route.md
├── references/              # 配置文件
│   ├── docker-compose.yml
│   ├── nginx.conf
│   ├── conf.d/              # nginx server 配置
│   ├── includes/            # 公共配置片段
│   ├── ssl/                 # SSL 证书目录
│   ├── pitfalls.md          # 踩坑记录
│   └── .env.example
```

## 与 infra-nginx 的区别

| 特性 | infra-nginx | edge-nginx |
|------|-------------|------------|
| 部署位置 | 内网 | DMZ 公网边界 |
| 流量来源 | 内网开发者 | 公网用户 |
| HTTPS | 不终止 | 终止 SSL |
| 访问控制 | 无 | IP 白名单 / 公开 |

## 安全加固

- TLS 1.2+ 协议
- 强加密套件
- HSTS 安全头
- X-Frame-Options / X-Content-Type-Options 等安全头
- IP 白名单访问控制（按域名 add-route）
- 限流 zone 预置三档（`edge_loose` / `edge_normal` / `edge_strict`），见 `references/conf/nginx/includes/rate-limit.conf`，server / location 按需 `include limit_req`

## 常见问题

### Q: HTTP 访问被重定向？

A: 这是预期行为。edge-nginx 统一使用 HTTPS，HTTP 请求会 301 重定向到 HTTPS。

### Q: 如何添加新的白名单域名？

A: 使用 add-route action：
```bash
/setup-edge-nginx add-route --env prod --domain <domain> --mode whitelist --ips "<ip-list>"
```

### Q: SSL 证书如何更新？

A: 上传新证书后，重启容器：
```bash
/setup-edge-nginx stop --env prod
/setup-edge-nginx start --env prod
```
