---
name: setup-infra-nginx
description: 使用 Docker Compose 部署内网唯一流量总闸，按四层域名规范（全局唯一/域级共用/非生产独有/环境级）预配置全部反代规则（含尚未部署的服务），涵盖 GitLab/Nexus/Harbor/Apollo/LGT 栈 UI/Consul-RabbitMQ 5环境 UI/Apollo Config 5环境/K3s 业务域名，TCP 透传 GitLab SSH 和 Nexus Docker。当开发者需要启动、停止、查看状态、验证 infra-nginx 服务时触发此 skill。
argument-hint: "[start|stop|status|verify|logs] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]"
disable-model-invocation: true
---

> **路径约定**：本文档中 `<skill_dir>` 指 SKILL.md 所在目录（安装后为 `~/.claude/skills/setup-infra-nginx`）。

# setup-infra-nginx — 内部 Web UI 统一入口

提供内部管理界面的统一入口，支持本地和远程服务器两种部署模式。

## 文档职责说明

| 文档 | 读者 | 职责 |
|------|------|------|
| **SKILL.md** | Claude Code（AI） | 技能执行指令 — 定义 frontmatter、action 路由、执行约束 |
| **README.md** | 人（开发者/用户） | 入门指引文档 — 安装教程、配置说明、功能介绍、使用示例 |

## 前置依赖

| 依赖 | 说明 |
|------|------|
| setup-dns | DNS 服务已部署，域名解析正常 |
| 端口 :80 可用 | infra-nginx 需占用 :80，Harbor 必须配置为非 80 端口（默认 :8880） |

## 配置

- 配置文件模板位于 `<skill_dir>/references/`
- 远程部署目录：`/opt/tech-stack/infra-nginx/`

> **配置渲染例外说明**：Nginx 服务的 `${VAR}` 由本地 Python 正则替换为 `.env` 实际值后再上传（不使用 envsubst，避免吞掉 nginx 内置变量 `$host`/`$remote_addr` 等）。详见 `references/pitfalls.md`。

## 用法

```
/setup-infra-nginx [action] [选项]

action: start（默认）| stop | status | verify | logs

选项:
  --host <ip>        部署目标 IP（默认: localhost）
  --user <user>      SSH 用户名（默认: root，仅远程）
  --password <pass>  SSH 密码（仅远程，与 --key 二选一）
  --key <path>       SSH 私钥路径（仅远程，与 --password 二选一）
  --ssh-port <n>     SSH 端口（默认: 22）
```

## Actions

| Action | 说明 |
|--------|------|
| `start` | 部署并启动 infra-nginx 容器（默认 action，含部署前确认流程） |
| `stop` | 停止并移除 infra-nginx 容器 |
| `status` | 查看 infra-nginx 容器运行状态 |
| `verify` | 验证 HTTP 反代和 TCP 透传正常 |
| `logs` | 查看 infra-nginx 容器日志 |

## 执行流程

1. 解析参数：提取 ACTION（默认 start）、HOST（默认 localhost）、SSH_USER（默认 root）、SSH_PORT（默认 22）、AUTH（password 或 key）
2. **start action 部署前确认**：检查目标机器端口和服务状态，与用户确认部署方案（详见 `actions/start.md`）
3. 读取 `<skill_dir>/actions/<action>.md` 按步骤执行

## 功能概览

| 功能 | 端口 | 说明 |
|------|------|------|
| HTTP 反向代理 | :80 | 内部管理 UI 统一入口 + 业务域名内网直达 K3s Traefik |
| TCP 透传 | :2222 | GitLab SSH |
| TCP 透传 | :8082 | Nexus Docker Registry |

## 代理服务清单（按四层域名规范）

### ① 全局唯一服务

| 域名 | 配置文件 | 后端 | 说明 |
|------|---------|------|------|
| `gitlab.renew.com` | 10-gitlab.conf | `${GITLAB_HOST}:8929` | GitLab Web |
| `nexus.renew.com` | 11-nexus.conf | `${NEXUS_HOST}:8081` | Nexus Web |
| `harbor.renew.com` | 12-harbor.conf | `${HARBOR_HOST}:8880` | Harbor Web |
| `dns.renew.com` | 13-dns.conf | `${DNS_HOST}:5380` | dnsmasq Web UI |

### ③ 非生产独有

| 域名 | 配置文件 | 后端 | 说明 |
|------|---------|------|------|
| `apollo.renew.com` | 20-apollo-portal.conf | `${APOLLO_HOST}:8070` | Apollo Portal |

### ④ 环境级 Apollo Config

| 域名 | 配置文件 | 后端 | 说明 |
|------|---------|------|------|
| `apollo-config-dev.renew.com` | 21-apollo-config.conf | `${APOLLO_HOST}:8601` | dev Config Service |
| `apollo-config-sit.renew.com` | 21-apollo-config.conf | `${APOLLO_HOST}:8602` | sit Config Service |
| `apollo-config-fat.renew.com` | 21-apollo-config.conf | `${APOLLO_HOST}:8603` | fat Config Service |
| `apollo-config-uat.renew.com` | 21-apollo-config.conf | `${APOLLO_HOST}:8604` | uat Config Service |
| `apollo-config-prod.renew.com` | 21-apollo-config.conf | `${APOLLO_PROD_HOST}:8605` | prod Config Service（生产网段独立机器） |

### ② 域级共用 UI（LGT 栈，nonprod/prod 各一套）

| 域名 | 配置文件 | 后端 | 说明 |
|------|---------|------|------|
| `grafana-nonprod-ui.renew.com` | 30-grafana.conf | `${GRAFANA_NONPROD_HOST}:3000` | 非生产 Grafana UI |
| `grafana-prod-ui.renew.com` | 30-grafana.conf | `${GRAFANA_PROD_HOST}:3000` | 生产 Grafana UI |
| `prometheus-nonprod-ui.renew.com` | 31-prometheus.conf | `${PROMETHEUS_NONPROD_HOST}:9090` | 非生产 Prometheus UI |
| `prometheus-prod-ui.renew.com` | 31-prometheus.conf | `${PROMETHEUS_PROD_HOST}:9090` | 生产 Prometheus UI |
| `alertmanager-nonprod-ui.renew.com` | 32-alertmanager.conf | `${ALERTMANAGER_NONPROD_HOST}:9093` | 非生产 Alertmanager UI |
| `alertmanager-prod-ui.renew.com` | 32-alertmanager.conf | `${ALERTMANAGER_PROD_HOST}:9093` | 生产 Alertmanager UI |

### ④ 环境级 Web UI（Consul、RabbitMQ × 5 环境）

| 域名 | 配置文件 | 后端 | 说明 |
|------|---------|------|------|
| `consul-{dev/sit/fat/uat/prod}-ui.renew.com` | 40-consul-ui.conf | `${CONSUL_ENV_HOST}:8500` | 各环境 Consul UI |
| `rabbitmq-{dev/sit/fat/uat/prod}-ui.renew.com` | 41-rabbitmq-ui.conf | `${RABBITMQ_ENV_HOST}:15672` | 各环境 RabbitMQ UI |

### ④ 业务应用（内网直达 K3s，nonprod / prod 双 K3s 集群分流）

| 域名 | 配置文件 | 后端 | 说明 |
|------|---------|------|------|
| `*.{dev,sit,fat,uat}.web/api.renew.com` | 50-k3s-business.conf | `${K3S_NONPROD_TRAEFIK_HOST}:${K3S_TRAEFIK_PORT}` | 非生产业务流量 → 非生产 K3s Traefik |
| `*.prod.web/api.renew.com`              | 50-k3s-business.conf | `${K3S_PROD_TRAEFIK_HOST}:${K3S_TRAEFIK_PORT}`    | 生产业务流量 → 生产 K3s Traefik |

> 变量在部署时由 Python 本地替换后上传，非 Docker Compose 环境变量。

## 关键约束

### --env 参数（C 类：全局唯一，不接受）

setup-infra-nginx 是全局唯一服务，传入 `--env` 参数将**立即报错退出**：
```
❌ setup-infra-nginx 是全局唯一服务（C 类），不接受 --env 参数，请移除后重试。
```

### 代理职责与域名规范

- infra-nginx **只代理 Web UI 和 HTTP 类接口**，不代理 Pod/微服务的原始 TCP 直连流量（MySQL/AMQP/OTLP 等）
- **hosts.lan 直连 vs infra-nginx 代理**：凡是 Pod 需要直接 TCP 连接的域名（mysql-dev/otel-nonprod 等）写入 hosts.lan，凡是浏览器/HTTP 访问的管理 UI 走泛解析→infra-nginx
- **-ui 后缀规范（全局适用）**：
  - 环境级：`{service}-{env}-ui.renew.com`（如 `consul-dev-ui.renew.com`）
  - 域级共用：`{service}-{nonprod|prod}-ui.renew.com`（如 `grafana-nonprod-ui.renew.com`）
  - 纯 UI 服务（无直连数据端口）同样适用，如 `grafana-nonprod-ui.renew.com`
- **GitLab/Nexus/Harbor/Apollo/dnsmasq**：全部通过 infra-nginx 代理（HTTP + TCP 透传），不写入 hosts.lan

### network_mode: host

infra-nginx 使用 host 网络模式，直接绑定宿主机 :80、:2222、:8082 端口。

### nginx 配置变量替换

nginx 配置中的 `${VAR}` 由 `actions/start.md` 中的 Python 脚本在本地替换为 `.env` 实际值后上传。

### 自定义超时服务不使用 include proxy_params

对需要自定义超时的服务（如 GitLab），直接写完整 proxy 配置，避免与 `proxy_params` 中的 `proxy_*_timeout` 指令重复定义导致 nginx 启动失败。

### 部署后 upstream 未就绪的预期行为

infra-nginx 在部署时一次性预配置全部反代规则（含尚未部署的服务）。上游服务尚未启动时对应域名访问返回 502/504，nginx 自身保持可用。各服务部署完成后域名即自动可用。

### 来源 IP 加固建议

infra-nginx 监听内网 :80/:2222/:8082，建议在生产环境通过宿主机防火墙（iptables / firewalld）或 nginx `allow/deny` 指令将来源 IP 限制为内网网段或 VPN 网段，避免暴露 GitLab/Nexus/Harbor/Apollo 等管理面到公网。

> 历史踩坑记录及解决方案详见 [pitfalls.md](references/pitfalls.md)，部署中遇到的新问题也请记录到该文件。

## 踩坑记录规则

> 部署过程中遇到的问题，按以下流程处理：
> 1. **修复模板**：将 fix 写入 `references/` 配置文件或 `actions/start.md` 流程步骤，确保下次部署自动生效
> 2. **记录 pitfalls.md**：在 `references/pitfalls.md` 中追加问题记录（现象、根因、修复方案）
> 3. **同步 start.md**：若涉及新增步骤，更新 `actions/start.md` 并调整步骤编号
