# setup-dns — 局域网 DNS 服务（dnsmasq）

使用 Docker 部署 dnsmasq，为整套微服务技术栈提供局域网内域名解析。所有基础设施服务通过 `*.renew.com` 域名访问，无需记忆 IP 地址。

| 项目 | 内容 |
|------|------|
| 镜像 | `jpillora/dnsmasq:latest` |
| 容器名 | `tech-dns` |
| 端口 | 53（DNS）/ 5380（Web UI） |
| 远程目录 | `/opt/tech-stack/dns/` |
| 资源限制 | 内存上限 128MB |

## 目录结构

```
setup-dns/
├── SKILL.md                    # Skill 路由指令（Claude 读取）
├── README.md                   # 入门指引（人类读取）
├── install.sh                  # 安装脚本
├── actions/
│   ├── start.md                # 启动 dnsmasq
│   ├── stop.md                 # 停止 dnsmasq
│   ├── status.md               # 查看状态和域名映射
│   ├── verify.md               # 验证域名解析
│   ├── logs.md                 # 查看 DNS 查询日志
│   └── configure.md            # 配置目标机器 DNS 指向 dnsmasq
└── references/
    ├── docker-compose.yml      # Docker Compose 配置
    ├── .env.example            # 环境变量模板
    ├── dnsmasq.conf            # dnsmasq 主配置
    └── hosts.lan               # 域名映射文件（核心）
```

## 安装

```bash
bash setup-dns/install.sh
```

## 工作原理

```
Pod 连接 mysql-dev.renew.com:3306（直连）
        ↓
K3s CoreDNS（转发 .renew.com 到 dnsmasq）
        ↓
┌──── dnsmasq ────────────────────────────────────────────────┐
│                                                              │
│ mysql-dev.renew.com → 查 hosts.lan → 返回 MySQL Dev IP      │ ← 直连域名：精确匹配
│ grafana-nonprod-ui.renew.com → 未命中 hosts.lan             │
│                   → 命中泛解析 address=/.renew.com/         │ ← 代理域名：泛解析兜底
│                   → 返回 infra-nginx IP                     │
│ baidu.com         → 未命中，转发上游 DNS                     │ ← 公网：上游解析
│                                                              │
└──────────────────────────────────────────────────────────────┘
        ↓
直连：Pod 直接连接 mysql-dev IP:3306
代理：浏览器 → infra-nginx:80 → Grafana:3000
```

**dnsmasq 只做域名→IP 翻译，不涉及端口，不经手实际数据流量。** 内存占用约 2-5 MB，对性能无影响。

**两层解析机制：**
- `hosts.lan` 精确匹配（直连层）：优先级高，Pod/微服务直连数据端口，多机时各服务可指向不同 IP
- `address=/.renew.com/${INFRA_NGINX_IP}` 泛解析（代理层兜底）：优先级低，未命中 hosts.lan 的所有 `*.renew.com` 统一解析到 infra-nginx

## 域名分类与访问说明

dnsmasq 按四层域名规范管理域名，核心原则：**只有 Pod/微服务需要直接 TCP 连接的域名才写入 hosts.lan**。

### 直连层：写入 hosts.lan（Pod 直连数据端口）

#### ④ 环境级直连 — 中间件（5 服务 × 5 环境）

| 域名 | 服务 | 端口 | 使用方 |
|------|------|------|--------|
| `mysql-{dev/sit/fat/uat/prod}.renew.com` | MySQL | 3306 | Spring Boot 数据源 |
| `redis-{dev/sit/fat/uat/prod}.renew.com` | Redis | 6379 | Redisson / Spring Cache |
| `mongodb-{dev/sit/fat/uat/prod}.renew.com` | MongoDB | 27017 | Spring Data MongoDB |
| `rabbitmq-{dev/sit/fat/uat/prod}.renew.com` | RabbitMQ | 5672 | Spring AMQP（AMQP 直连，管理 UI 另用 rabbitmq-{env}-ui） |
| `consul-{dev/sit/fat/uat/prod}.renew.com` | Consul | 8500 | Spring Cloud 服务注册发现（UI 另用 consul-{env}-ui） |

#### ② 域级直连 — 可观测性与计算底座（6 服务 × 2 域）

| 域名 | 服务 | 端口 | 使用方 |
|------|------|------|--------|
| `otel-{nonprod/prod}.renew.com` | OTel Collector | 4317/4318 | Micrometer / OTel SDK 上报（OTLP 直连） |
| `loki-{nonprod/prod}.renew.com` | Loki | 3100 | OTel Collector 推送日志 |
| `tempo-{nonprod/prod}.renew.com` | Tempo | 14317/14318/3200 | OTel Collector 推送链路追踪(:14317 gRPC/:14318 HTTP) / Grafana 查询(:3200) |
| `prometheus-{nonprod/prod}.renew.com` | Prometheus | 9090 | OTel Collector 推送指标（UI 另用 prometheus-{nonprod/prod}-ui） |
| `alertmanager-{nonprod/prod}.renew.com` | Alertmanager | 9093 | Prometheus alerting 推送 / Loki ruler 推送（UI 另用 alertmanager-{nonprod/prod}-ui） |
| `k3s-{nonprod/prod}.renew.com` | K3s 集群 | 8083 | edge-nginx / infra-nginx 转发业务流量的目标 |

> hosts.lan 合计 **37 条**精确记录，全部使用 `CHANGE_ME_*` 占位符。

### 代理层：不写 hosts.lan，由泛解析→infra-nginx 处理

`dnsmasq.conf` 的泛解析 `address=/.renew.com/${INFRA_NGINX_IP}` 将所有未命中 hosts.lan 的 `*.renew.com` 解析到 infra-nginx，以下域名**不需要写入 hosts.lan**：

| 域名示例 | 服务 | 浏览器访问地址 |
|---------|------|--------------|
| `grafana-nonprod-ui.renew.com` | Grafana（非生产） | `http://grafana-nonprod-ui.renew.com` |
| `grafana-prod-ui.renew.com` | Grafana（生产） | `http://grafana-prod-ui.renew.com` |
| `prometheus-nonprod-ui.renew.com` | Prometheus UI | `http://prometheus-nonprod-ui.renew.com` |
| `alertmanager-nonprod-ui.renew.com` | Alertmanager UI | `http://alertmanager-nonprod-ui.renew.com` |
| `consul-{env}-ui.renew.com` | Consul UI | `http://consul-dev-ui.renew.com` |
| `rabbitmq-{env}-ui.renew.com` | RabbitMQ 管理 | `http://rabbitmq-dev-ui.renew.com` |
| `apollo.renew.com` | Apollo Portal | `http://apollo.renew.com` |
| `apollo-config-{env}.renew.com` | Apollo Config | `http://apollo-config-dev.renew.com` |
| `gitlab.renew.com` | GitLab | `http://gitlab.renew.com` |
| `nexus.renew.com` | Nexus | `http://nexus.renew.com` |
| `harbor.renew.com` | Harbor | `http://harbor.renew.com` |
| `dns.renew.com` | dnsmasq Web UI | `http://dns.renew.com` |

> **新增 infra-nginx 代理服务时**：只需在 nginx conf.d 加 server block，无需修改 hosts.lan，泛解析自动覆盖新域名。

### 不在 dnsmasq 维护

| 域名类型 | 示例 | 管理方式 |
|---------|------|---------|
| 业务前端 | `demo.fat.web.renew.com` | 泛解析 → infra-nginx → K3s Traefik |
| 业务 API | `gateway.fat.api.renew.com` | 泛解析 → infra-nginx → K3s Traefik |

## 谁需要指向 dnsmasq？

理解这一点是正确配置 DNS 的关键：

| 客户端类型 | 是否需要指向 dnsmasq | 原因 |
|-----------|-------------------|------|
| **所有服务器**（93、97 等） | **必须** | Docker 容器内需要解析 `mysql-{env}.renew.com` 等基础设施域名 |
| **开发者电脑**（访问内部 Web UI） | **需要** | 浏览器访问 `grafana-nonprod-ui.renew.com` 需要 dnsmasq 解析 |
| **开发者电脑**（仅访问业务应用） | 不需要 | 业务域名用本机 hosts 文件，不依赖 dnsmasq |
| **K3s Pod** | **必须**（通过 CoreDNS 转发） | Pod 需解析 `mysql-{env}.renew.com`，CoreDNS 将 `.renew.com` 转发给 dnsmasq |

> 实际上，开发者电脑如果想访问 `grafana-nonprod-ui.renew.com` 等内部 Web UI，**最简单的方式就是把 DNS 指向 dnsmasq**（代理层域名全部自动生效），而不是逐条加 hosts 记录。

## 快速开始

### 1. 部署 dnsmasq

```bash
/setup-dns start
```

### 2. 编辑域名映射

编辑 `/opt/tech-stack/dns/hosts.lan`，取消注释并填入实际 IP：

**hosts.lan 参考结构（将 CHANGE_ME_* 替换为实际 IP）：**
```
# ====== ④ 环境级直连 — 中间件 ======
CHANGE_ME_MYSQL_DEV_IP    mysql-dev.renew.com
CHANGE_ME_MYSQL_SIT_IP    mysql-sit.renew.com
CHANGE_ME_MYSQL_FAT_IP    mysql-fat.renew.com
CHANGE_ME_MYSQL_UAT_IP    mysql-uat.renew.com
CHANGE_ME_MYSQL_PROD_IP   mysql-prod.renew.com
# Redis / MongoDB / RabbitMQ / Consul 各 5 条，结构相同

# ====== ② 域级直连 — 可观测性 ======
CHANGE_ME_OTEL_NONPROD_IP          otel-nonprod.renew.com
CHANGE_ME_OTEL_PROD_IP             otel-prod.renew.com
# Loki / Tempo / Prometheus / Alertmanager / K3s 结构相同
CHANGE_ME_ALERTMANAGER_NONPROD_IP  alertmanager-nonprod.renew.com
CHANGE_ME_ALERTMANAGER_PROD_IP     alertmanager-prod.renew.com
CHANGE_ME_K3S_NONPROD_IP           k3s-nonprod.renew.com
CHANGE_ME_K3S_PROD_IP              k3s-prod.renew.com

# 合计 37 条；Web UI / Apollo / GitLab 等代理域名不写入
```

**多机扩展时：** 只修改对应域名的 IP（如 `mysql-prod.renew.com` 改为生产数据库机器 IP），其余不变。

修改后重启生效：
```bash
docker restart tech-dns
```

### 3. 配置客户端 DNS

**方式一：路由器配置（全网生效，零客户端配置）**

在路由器 DHCP 设置中：
- 主 DNS → dnsmasq 所在机器 IP
- 备 DNS → 114.114.114.114

**方式二：逐台配置（无法控制路由器时）**

```bash
# 远程服务器（每台执行一次，--dns-server 是 dnsmasq 所在机器的 IP）
/setup-dns configure --host <SERVER1_IP> --dns-server <DNS_IP> --user root --key ~/.ssh/id_rsa
/setup-dns configure --host <SERVER2_IP> --dns-server <DNS_IP> --user root --key ~/.ssh/id_rsa

# 本机（开发者电脑）
/setup-dns configure --dns-server <DNS_IP>
```

**方式三：手动配置**（将 `<DNS_SERVER_IP>` 替换为 dnsmasq 所在机器的 IP）

**Linux**（systemd-resolved）：

```bash
# 推荐方式：条件转发（仅 *.renew.com 走 dnsmasq）
sudo mkdir -p /etc/systemd/resolved.conf.d/
sudo tee /etc/systemd/resolved.conf.d/tech-stack-dns.conf <<EOF
[Resolve]
DNS=<DNS_IP>
Domains=~renew.com
EOF
sudo systemctl restart systemd-resolved

# 备选方式：全局替换（所有域名走 dnsmasq）
echo "nameserver <DNS_IP>" | sudo tee /etc/resolv.conf
echo "nameserver 114.114.114.114" | sudo tee -a /etc/resolv.conf
```

**macOS**（原生支持条件转发）：

```bash
# 推荐方式：条件转发（仅 *.renew.com 走 dnsmasq）
sudo mkdir -p /etc/resolver/
echo "nameserver <DNS_IP>" | sudo tee /etc/resolver/renew.com

# 备选方式：全局替换
# 系统偏好设置 → 网络 → 高级 → DNS → 添加 <DNS_IP>
```

**Windows**：

```powershell
# 推荐方式：NRPT 条件转发（仅 *.renew.com 走 dnsmasq，不影响公司 DNS）
Add-DnsClientNrptRule -Namespace ".renew.com" -NameServers "<DNS_IP>"
Get-DnsClientNrptRule  # 验证规则
Clear-DnsClientCache   # 刷新缓存

# 删除规则：Remove-DnsClientNrptRule -Namespace ".renew.com"

# 备选方式：全局替换（所有域名走 dnsmasq）
Set-DnsClientServerAddress -InterfaceAlias "以太网" -ServerAddresses ("<DNS_IP>","114.114.114.114")
```

### 4. 验证

```bash
/setup-dns verify
```

或手动测试：
```bash
nslookup grafana-nonprod-ui.renew.com
nslookup baidu.com
```

## .env 配置说明

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DNS_WEB_PORT` | 5380 | Web 管理界面端口 |
| `DNS_WEB_USER` | admin | Web UI 用户名 |
| `DNS_WEB_PASSWORD` | — | Web UI 密码（必须修改） |
| `INFRA_NGINX_IP` | — | infra-nginx 所在机器 IP（泛解析兜底目标，必须修改） |
| `UPSTREAM_DNS_PRIMARY` | 114.114.114.114 | 上游 DNS 主（解析公网域名）；海外环境建议 `1.1.1.1` 或 `8.8.8.8` |
| `UPSTREAM_DNS_SECONDARY` | 8.8.8.8 | 上游 DNS 备；国内环境建议 `223.5.5.5` |

> dnsmasq 监听端口固定为 :53（容器使用 host 网络，不可改）。dnsmasq 服务器 IP 通过 configure action 的 `--dns-server` 命令行参数显式传入，不在 .env 中存储以避免漂移。

## 域名规划

| 域名类型 | 示例 | 解析方式 | 解析到 |
|---------|------|---------|--------|
| ④ 环境级直连 | `mysql-dev.renew.com` | hosts.lan 精确匹配 | 各环境服务所在机器 IP |
| ② 域级直连 | `otel-nonprod.renew.com` | hosts.lan 精确匹配 | 可观测性服务所在机器 IP |
| 内部 Web UI | `grafana-nonprod-ui.renew.com` | dnsmasq.conf 泛解析兜底 | infra-nginx IP |
| ① 全局唯一 | `gitlab.renew.com` | dnsmasq.conf 泛解析兜底 | infra-nginx IP |
| 业务前端/API | `demo.fat.web.renew.com` | 泛解析 → infra-nginx → K3s Traefik | infra-nginx IP |
| 微服务注册 | `*.service.consul` | Consul DNS（自动注册） | 动态 |
| 公网域名 | `github.com` | 转发上游 DNS | 公网 |

## 与其他服务的关系

dnsmasq 配置好后，各服务 `.env` 中的 `*_HOST` 变量使用多环境域名：

```bash
# setup-otel-collector/.env（nonprod 示例）
TEMPO_HOST=tempo-nonprod.renew.com
LOKI_HOST=loki-nonprod.renew.com
PROMETHEUS_HOST=prometheus-nonprod.renew.com

# setup-prometheus/.env（dev 环境示例）
CONSUL_HOST=consul-dev.renew.com

# setup-grafana/.env（nonprod 示例）
PROMETHEUS_HOST=prometheus-nonprod.renew.com
TEMPO_HOST=tempo-nonprod.renew.com
LOKI_HOST=loki-nonprod.renew.com
```

## 注意事项

- **部署顺序**：dnsmasq 应最先部署，其他服务部署前先完成 DNS 配置
- **53 端口冲突**：Ubuntu 的 systemd-resolved 默认监听 53 端口，需先停止或使用条件转发
- **hosts.lan 修改后需重启**：`docker restart tech-dns`
- **dnsmasq 宕机影响**：所有使用此 DNS 的机器将无法解析 `*.renew.com` 域名，公网域名可通过备用 DNS 解析
- **Windows DNS 缓存**：修改 DNS 后可能需要刷新缓存：`ipconfig /flushdns`
- **直连层域名需指定端口**：DNS 只做域名→IP 映射，直连基础设施时仍需端口（如 `jdbc:mysql://mysql-dev.renew.com:3306`）
- **代理层域名无需端口**：内部 Web UI 通过 infra-nginx 代理，浏览器访问 `http://grafana-nonprod-ui.renew.com` 即可（infra-nginx 内部转发到 :3000）

## Docker 环境兼容性

### 前置条件：内核参数

dnsmasq 以 Docker 容器方式部署时，宿主机**必须已配置**以下内核参数，否则容器端口映射不通：

```bash
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
```

配置方法见 `references/deployment-principles.md` 前置准备章节。

### bind-dynamic 配置说明

dnsmasq 默认使用 wildcard socket（`listen-address=0.0.0.0`）监听所有接口。在安装了 Docker 的机器上，系统会多出 `docker0`、`br-*` 等虚拟网桥接口。dnsmasq 收到 DNS 查询后会通过 netlink 枚举所有网卡地址，发现这些非预期接口后**静默丢弃查询**——不报错、不记日志、不响应客户端。

`dnsmasq.conf` 中已配置 `bind-dynamic` 解决此问题：

```
bind-dynamic
```

- 仅绑定启动时已存在的接口，避免被 Docker 网桥干扰
- 同时允许运行时动态发现新接口（比 `bind-interfaces` 更灵活）
- 如果使用原生安装（非 Docker），也可以用 `bind-interfaces` + 显式 `listen-address=127.0.0.1` + `listen-address=<宿主机IP>` 替代

### 故障排查

dnsmasq 容器 healthy 但 DNS 查询超时（典型表现：`dig @127.0.0.1` 无响应、容器日志为空）的根因排查步骤详见 [`references/pitfalls.md`](references/pitfalls.md)，含 strace / tcpdump / SIGUSR1 转储等定位手法。
