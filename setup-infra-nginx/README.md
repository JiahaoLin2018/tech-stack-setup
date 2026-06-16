# setup-infra-nginx

使用 Docker Compose 部署内部 Web UI 统一入口，反向代理基础设施管理界面，支持本地和远程服务器两种部署模式。

## 安装

```bash
bash install.sh
```

安装后即可在 Claude Code 中使用 `/setup-infra-nginx` 命令。

## 前提条件

- Harbor 使用 :8880 端口（确保 :80 端口可用）
- DNS 服务正常运行
- 远程模式：SSH 可连接目标服务器；密码模式需本地安装 `sshpass`

## 支持的命令

| 命令 | 说明 |
|------|------|
| `/setup-infra-nginx start` | 启动 infra-nginx（检查端口 → 上传配置 → 启动容器 → 健康验证） |
| `/setup-infra-nginx stop` | 停止并移除容器 |
| `/setup-infra-nginx status` | 查看容器运行状态及端口监听 |
| `/setup-infra-nginx verify` | 验证 HTTP 反代和 TCP 透传 |
| `/setup-infra-nginx logs` | 查看容器日志（最近 50 行） |

## 远程部署示例

```bash
# 使用密码部署到远程服务器
/setup-infra-nginx start --host <INFRA_NGINX_IP> --user root --password <your-password>

# 使用 SSH 密钥部署
/setup-infra-nginx start --host <INFRA_NGINX_IP> --key ~/.ssh/id_rsa

# 查看远程服务状态
/setup-infra-nginx status --host <INFRA_NGINX_IP> --key ~/.ssh/id_rsa
```

## 功能说明

infra-nginx 作为内部管理界面的统一入口 + 业务域名内网直达网关：

| 功能 | 端口 | 说明 |
|------|------|------|
| HTTP 反向代理 | :80 | 内部管理 UI 统一入口 |
| HTTP 反向代理 | :80 | 业务域名内网直达 K3s Traefik |
| TCP 透传 | :2222 | GitLab SSH → ${GITLAB_HOST}:2222 |
| TCP 透传 | :8082 | Nexus Docker → ${NEXUS_HOST}:8082 |

## 代理服务清单（四层域名规范）

### ① 全局唯一服务

| 域名 | 目标 | 说明 |
|------|------|------|
| `gitlab.renew.com` | `${GITLAB_HOST}:8929` | GitLab Web（跨机） |
| `nexus.renew.com` | `${NEXUS_HOST}:8081` | Nexus Web（跨机） |
| `harbor.renew.com` | `${HARBOR_HOST}:8880` | Harbor Registry |
| `dns.renew.com` | `${DNS_HOST}:5380` | dnsmasq Web UI |

### ③ 非生产独有

| 域名 | 目标 | 说明 |
|------|------|------|
| `apollo.renew.com` | `${APOLLO_HOST}:8070` | Apollo Portal（仅非生产访问）|

### ④ 环境级 Apollo Config Service

| 域名 | 目标 | 说明 |
|------|------|------|
| `apollo-config-dev/sit/fat/uat.renew.com` | `${APOLLO_HOST}:8601-8604` | 非生产 Config Service |
| `apollo-config-prod.renew.com` | `${APOLLO_PROD_HOST}:8605` | 生产 Config Service（独立网段）|

### ② 域级共用 UI（nonprod/prod 各一套）

| 域名 | 目标 | 说明 |
|------|------|------|
| `grafana-nonprod-ui.renew.com` | `${GRAFANA_NONPROD_HOST}:3000` | 非生产 Grafana |
| `grafana-prod-ui.renew.com` | `${GRAFANA_PROD_HOST}:3000` | 生产 Grafana |
| `prometheus-nonprod-ui.renew.com` | `${PROMETHEUS_NONPROD_HOST}:9090` | 非生产 Prometheus UI |
| `prometheus-prod-ui.renew.com` | `${PROMETHEUS_PROD_HOST}:9090` | 生产 Prometheus UI |
| `alertmanager-nonprod-ui.renew.com` | `${ALERTMANAGER_NONPROD_HOST}:9093` | 非生产 Alertmanager UI |
| `alertmanager-prod-ui.renew.com` | `${ALERTMANAGER_PROD_HOST}:9093` | 生产 Alertmanager UI |

### ④ 环境级 Web UI（5 环境独立）

| 域名 | 目标 | 说明 |
|------|------|------|
| `consul-{dev/sit/fat/uat/prod}-ui.renew.com` | `${CONSUL_{ENV}_HOST}:8500` | 各环境 Consul UI |
| `rabbitmq-{dev/sit/fat/uat/prod}-ui.renew.com` | `${RABBITMQ_{ENV}_HOST}:15672` | 各环境 RabbitMQ 管理 UI |

### ④ 业务应用（内网直达 K3s Traefik，nonprod / prod 双 K3s 分流）

| 域名 | 目标 | 说明 |
|------|------|------|
| `*.{dev,sit,fat,uat}.web/api.renew.com` | `${K3S_NONPROD_TRAEFIK_HOST}:${K3S_TRAEFIK_PORT}` | 非生产业务流量 → 非生产 K3s |
| `*.prod.web/api.renew.com` | `${K3S_PROD_TRAEFIK_HOST}:${K3S_TRAEFIK_PORT}` | 生产业务流量 → 生产 K3s |

> 所有 ${VAR} 在部署时由 Python 本地替换后上传，变量值来自 `.env` 文件。

## 目录结构

```
setup-infra-nginx/
├── SKILL.md                      # AI 执行指令
├── actions/
│   ├── start.md                  # 启动流程（本地+远程）
│   ├── stop.md
│   ├── status.md
│   ├── verify.md
│   └── logs.md
├── references/
│   ├── docker-compose.yml        # 生产级配置
│   ├── .env.example              # 环境变量模板
│   └── conf/nginx/
│       ├── nginx.conf            # 主配置（http + stream）
│       ├── proxy_params          # 通用代理参数
│       └── conf.d/               # server block 配置
├── README.md
└── install.sh
```

## 注意事项

- 使用 host 网络模式，直接绑定宿主机端口
- 前置条件：Harbor 必须配置为 :8880（避免占用 :80）
- DNS 泛解析必须指向本机 IP（`INFRA_NGINX_IP` 配置在 setup-dns .env 中）
- `K3S_NONPROD_TRAEFIK_HOST` / `K3S_PROD_TRAEFIK_HOST` 必须使用 K3s 节点的宿主机实际 IP，不能用 127.0.0.1（K3s svclb 通过 iptables DNAT，不监听 loopback）
- nginx 配置中的 `${VAR}` 由本地 Python 正则替换为 `.env` 实际值后上传
- 已预配置的反代规则在上游服务部署完成前返回 502/504，nginx 自身保持可用
- 生产环境建议通过宿主机防火墙或 nginx `allow/deny` 指令将 :80 / :2222 / :8082 来源 IP 限制为内网/VPN 段

## 部署前确认

部署前会自动检查目标机器端口与跨机 upstream 可达性，仅展示信息后让用户决定继续或取消：

| 选项 | 说明 |
|------|------|
| 1. 继续部署（默认） | 跨机 upstream 不可达仅 WARNING；本机端口被占由用户先清理后重试 |
| 2. 取消部署 | 终止部署流程 |

> upstream 不可达不阻断部署 —— 蓝图原则：infra-nginx 部署时预配置全部反代规则，未就绪的 upstream 访问返回 502 属预期行为，不影响 nginx 自身运行。

### 端口检查清单（任一被占需用户先清理后重试）

| 端口 | 用途 | 冲突处理 |
|------|------|---------|
| :80 | HTTP 反代 | 若被 Harbor 占用，需先迁移到 :8880 |
| :2222 | GitLab SSH 透传 | 若被占用，确认是否与现有 SSH 服务冲突 |
| :8082 | Nexus Docker 透传 | 若被占用，确认是否与现有 Docker Registry 冲突 |

