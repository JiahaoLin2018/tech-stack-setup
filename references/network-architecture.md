# 网络架构

> **本文档定位**：详细说明四层域名规范、DNS 解析机制、双入口流量路径与多环境路由。
> 架构权威：[architecture-blueprint.md](../architecture-blueprint.md) 第三部分。

---

## 四层域名命名规范

所有内部服务统一使用 `*.renew.com`。按服务的部署范围分四层：

| 层级 | 命名规范 | 示例 | 解析方式 | 适用组件 |
|------|---------|------|---------|---------|
| ① 全局唯一 | `{service}.renew.com` | `gitlab.renew.com` / `harbor.renew.com` / `dns.renew.com` | 泛解析 → infra-nginx | DNS Web UI / GitLab / Nexus / Harbor |
| ② 域级直连数据端口 | `{service}-{nonprod\|prod}.renew.com` | `otel-nonprod.renew.com:4317` / `prometheus-prod.renew.com:9090` | **hosts.lan** 精确匹配 | OTel Collector / Loki / Tempo / Prometheus / Alertmanager / K3s（Pod 直连） |
| ② 域级共用 UI | `{service}-{nonprod\|prod}-ui.renew.com` | `grafana-nonprod-ui.renew.com` | 泛解析 → infra-nginx | Grafana / Prometheus UI / Alertmanager UI |
| ③ 非生产独有 | `{service}.renew.com`（仅非生产域） | `apollo.renew.com` | 泛解析 → infra-nginx | Apollo Portal |
| ④ 环境级直连 | `{service}-{env}.renew.com` | `mysql-dev.renew.com:3306` | **hosts.lan** 精确匹配 | MySQL / Redis / MongoDB / RabbitMQ / Consul |
| ④ 环境级 Web UI | `{service}-{env}-ui.renew.com` | `consul-dev-ui.renew.com` | 泛解析 → infra-nginx | Consul UI / RabbitMQ UI |
| ④ Apollo Config | `apollo-config-{env}.renew.com` | `apollo-config-fat.renew.com` | 泛解析 → infra-nginx | 各环境 Apollo Config Service（含 prod 跨网段） |
| ④ 业务应用 | `{project}.{env}.{web\|api}.renew.com` | `zoro.fat.web.renew.com` | edge-nginx (DMZ) / infra-nginx → K3s Traefik :8083 | K3s 业务前端 / Gateway / 微服务 |

### 速查规则

| 区分维度 | 直连数据端口 | 管理 Web UI |
|---------|------------|------------|
| 域名形态 | `{service}[-env].renew.com` | 加 `-ui` 后缀：`{service}[-env]-ui.renew.com` |
| 是否写 hosts.lan | **是**，精确匹配 | 否，由泛解析 → infra-nginx 兜底 |
| 访问端口 | **必须带端口**（如 `mysql-dev.renew.com:3306`） | 不带端口（如 `http://consul-dev-ui.renew.com`） |
| 适用层级 | ② 域级 + ④ 环境级 | ② 域级 + ④ 环境级 |

> Prometheus 同时拥有直连域名（`prometheus-nonprod.renew.com:9090`，hosts.lan）和 UI 域名（`prometheus-nonprod-ui.renew.com`，反代）。

---

## hosts.lan 必备 37 条

```
# ④ 环境级直连 — 5 服务 × 5 环境 = 25 条
mysql-{dev,sit,fat,uat,prod}.renew.com         → 各环境 MySQL IP
redis-{dev,sit,fat,uat,prod}.renew.com         → 各环境 Redis IP
mongodb-{dev,sit,fat,uat,prod}.renew.com       → 各环境 MongoDB IP
rabbitmq-{dev,sit,fat,uat,prod}.renew.com      → 各环境 RabbitMQ IP（AMQP 直连）
consul-{dev,sit,fat,uat,prod}.renew.com        → 各环境 Consul IP（API 直连）

# ② 域级直连 — 6 服务 × 2 域 = 12 条
otel-{nonprod,prod}.renew.com                  → 各域 OTel Collector IP（OTLP 推送 :4317/:4318）
loki-{nonprod,prod}.renew.com                  → 各域 Loki IP（OTLP HTTP 推送 :3100/otlp）
tempo-{nonprod,prod}.renew.com                 → 各域 Tempo IP（OTLP gRPC 推送 :14317 / Grafana 查询 :3200）
prometheus-{nonprod,prod}.renew.com            → 各域 Prometheus IP（指标推送 / Grafana 查询 :9090）
alertmanager-{nonprod,prod}.renew.com          → 各域 Alertmanager IP（Loki ruler / Prometheus alerting 推送 :9093）
k3s-{nonprod,prod}.renew.com                   → 各域 K3s 集群节点 IP（edge-nginx / infra-nginx 转发目标 :8083）
```

**不写入 hosts.lan 的域名**（全部由泛解析 → infra-nginx 处理）：

- ① 全局唯一：gitlab / nexus / harbor / dns
- ② 域级共用 UI：grafana-{nonprod,prod}-ui / prometheus-{nonprod,prod}-ui / alertmanager-{nonprod,prod}-ui
- ③ 非生产独有：apollo
- ④ 环境级 Web UI：consul-{env}-ui / rabbitmq-{env}-ui
- ④ Apollo Config：apollo-config-{env}
- ④ 业务应用：*.{env}.web/api

---

## DNS 解析机制

dnsmasq 采用两层解析机制简化域名管理：

- **区一：精确匹配**（hosts.lan）— 写入直连数据端口的 IP 映射，对应"必备 37 条"
- **区二：泛解析兜底**（dnsmasq.conf `address=/.renew.com/${INFRA_NGINX_IP}`）— 兜底所有未精确指定的 `*.renew.com`，全部转发给 infra-nginx 反代

> **设计好处**：新增内部 Web UI 只需在 infra-nginx 加 server block，无需修改 DNS 配置；泛解析与精确匹配互不冲突。

### 解析优先级

```
hosts.lan 精确匹配  >  dnsmasq.conf address=/.renew.com/${INFRA_NGINX_IP}（泛解析兜底）  >  上游公网 DNS
```

### K3s Pod 解析链路

```
K3s Pod 查询 mysql-fat.renew.com
     │
     ▼
K3s CoreDNS（匹配 .renew.com）       ← coredns-custom ConfigMap 配置
     │
     │ forward .renew.com ${DNS_SERVER_IP}   ← 转发目标用 IP 是铁律二的合理例外
     ▼
转发到 dnsmasq (:53)
     │
     ▼
hosts.lan 精确匹配 → 返回 FAT MySQL IP
     │
     ▼
Pod 直连 mysql-fat.renew.com:3306（不再经过 DNS）
```

### CoreDNS 不会循环

| 步骤 | 查询方向 | 说明 |
|------|---------|------|
| 1 | Pod → CoreDNS | Pod 向 K3s CoreDNS 查询 `mysql-fat.renew.com` |
| 2 | CoreDNS 检查 Kubernetes 插件 | 不匹配 `.svc.cluster.local`，跳过 |
| 3 | CoreDNS 检查 forward 规则 | 匹配 `renew.com`，作为 DNS 客户端向 dnsmasq 发起查询 |
| 4 | dnsmasq 返回 IP | 查 hosts.lan，返回环境对应 IP |
| 5 | CoreDNS 返回给 Pod | Pod 拿到 IP 后直连，不再经过任何 DNS |

> **关键**：CoreDNS Kubernetes 插件优先匹配 `.svc.cluster.local`；forward 是单向的（CoreDNS 是 dnsmasq 的客户端，dnsmasq 不会反查）；Pod 拿到 IP 后直连。

### 域名类型对照

| 域名类型 | 示例 | CoreDNS 处理方式 |
|---------|------|-----------------|
| K8s 内部 Service | `demo-frontend.fat.svc.cluster.local` | Kubernetes 插件直接返回 ClusterIP |
| 基础设施域名 | `mysql-fat.renew.com` | forward 到 dnsmasq → 返回 hosts.lan IP |
| 公网域名 | `github.com` | forward 到上游公网 DNS |

---

## 双入口流量路径

本架构采用 **双入口分离设计**：公网业务流量走 DMZ 区 edge-nginx（HTTPS 终止 + 安全边界，nonprod / prod 物理隔离），内网管理流量与开发联调走局域网 infra-nginx（HTTP 反代 + Web UI 统一入口）。两条路径**最终汇合于 K3s Traefik :8083**，由 IngressRoute 路由到业务 Pod。

### 公网流量（DMZ 入口）— 双 K3s 物理隔离

```
┌────────────────────────────────────────────────────────────────────┐
│  公网用户                                                            │
│      │                                                              │
│      ▼                                                              │
│  公网 DNS 解析 *.{env}.web/api.renew.com                            │
│      │                                                              │
│      │ nonprod 环境 → 解析至非生产 DMZ 公网 IP                        │
│      │ prod 环境    → 解析至生产 DMZ 公网 IP                          │
│      ▼                                                              │
│  edge-nginx 实例 :443 (HTTPS 终止)                                   │
│      │                                                              │
│      │ nonprod 实例 (DMZ 独立机房 + 测试证书)                          │
│      │   └─ *.{dev,sit,fat,uat}.{web,api} → k3s-nonprod.renew.com:8083 │
│      │ prod 实例 (DMZ 独立机房 + 生产证书 + 物理孤岛)                  │
│      │   └─ *.prod.{web,api} → k3s-prod.renew.com:8083              │
│      ▼                                                              │
│  K3s Traefik Ingress :8083 → 业务 Pod                                │
│                                                                     │
│  访问控制：edge-nginx 支持公开访问 / IP 白名单（按域名精确控制）         │
│  HTTP :80 → HTTPS :443 强制 301 重定向                                │
└────────────────────────────────────────────────────────────────────┘
```

### 内网流量（infra-nginx 入口）— 双 K3s 分流

```
┌────────────────────────────────────────────────────────────────────┐
│  内网开发者 / 运维                                                   │
│      │                                                              │
│      ▼                                                              │
│  dnsmasq 泛解析 → infra-nginx :80                                    │
│      │                                                              │
│      ├─ {service}.renew.com → 全局服务（GitLab/Nexus/Harbor）         │
│      ├─ {service}-{nonprod\|prod}-ui → 域级 UI（Grafana/Prom UI）     │
│      ├─ apollo.renew.com → Apollo Portal                            │
│      ├─ apollo-config-{env}.renew.com → 各环境 Apollo Config         │
│      ├─ {service}-{env}-ui → 环境级 UI（Consul UI / RabbitMQ UI）     │
│      └─ *.{env}.{web\|api} 业务域名内网直达：                          │
│            ├─ *.{dev,sit,fat,uat} → k3s-nonprod.renew.com:8083       │
│            └─ *.prod              → k3s-prod.renew.com:8083          │
└────────────────────────────────────────────────────────────────────┘
```

### TCP 透传（infra-nginx stream 块）

```
git@gitlab.renew.com -p 2222
     ├─► infra-nginx :2222 ──stream──► ${GITLAB_HOST}:2222 (GitLab SSH)

docker push nexus.renew.com:8082/myimage
     ├─► infra-nginx :8082 ──stream──► ${NEXUS_HOST}:8082 (Nexus Docker Registry)
```

> **跨机部署约束**：infra-nginx host 网络模式直接监听宿主机 :2222 / :8082，必须与 GitLab 容器（宿主机映射 :2222→:22）和 Nexus 容器（:8082→:8082）跨主机部署，否则端口冲突。蓝图阶段一 1-2 / 1-3 / 1-4 默认跨机。

---

## Pod 直连基础设施（不经过 Nginx）

```
┌──────────────────────────────────────────────────────────────────────────┐
│   K8s Pod / Spring Boot 微服务（fat 环境示例）                             │
│                                                                          │
│   环境变量配置（由 setup-gitlab-runner 的 app.sh 注入）:                  │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │ SPRING_DATASOURCE_URL: jdbc:mysql://mysql-fat.renew.com:3306/... │  │
│   │ SPRING_DATA_REDIS_HOST: redis-fat.renew.com                      │  │
│   │ SPRING_CLOUD_CONSUL_HOST: consul-fat.renew.com                   │  │
│   │ APOLLO_META: http://apollo-config-fat.renew.com                  │  │
│   │ OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-nonprod.renew.com:4317  │  │
│   │ OTEL_RESOURCE_ATTRIBUTES: deployment.environment=fat,            │  │
│   │                           service.namespace=fat                  │  │
│   │ OTEL_METRICS_EXPORTER: none                                      │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│   解析链路:                                                               │
│     mysql-fat.renew.com   → CoreDNS → dnsmasq → 各环境 MySQL IP:3306     │
│     consul-fat.renew.com  → CoreDNS → dnsmasq → 各环境 Consul IP:8500    │
│     otel-nonprod.renew.com → CoreDNS → dnsmasq → nonprod OTel IP:4317    │
└──────────────────────────────────────────────────────────────────────────┘
```

> **核心原则**：所有微服务 → 基础设施直接通过 `*.renew.com` 域名 DNS 直连，不经过任何 Nginx。

---

## 多环境 DNS 解析对照

| 环境 | env→domainEnv 映射 | 数据库直连 | OTel 推送目标 | Apollo Meta |
|------|-------------------|-----------|--------------|-------------|
| dev | nonprod | `mysql-dev.renew.com` | `otel-nonprod.renew.com:4317` | `apollo-config-dev.renew.com` |
| sit | nonprod | `mysql-sit.renew.com` | `otel-nonprod.renew.com:4317` | `apollo-config-sit.renew.com` |
| fat | nonprod | `mysql-fat.renew.com` | `otel-nonprod.renew.com:4317` | `apollo-config-fat.renew.com` |
| uat | nonprod | `mysql-uat.renew.com` | `otel-nonprod.renew.com:4317` | `apollo-config-uat.renew.com` |
| prod | prod | `mysql-prod.renew.com` | `otel-prod.renew.com:4317` | `apollo-config-prod.renew.com` |

> env→domainEnv 映射规则：dev/sit/fat/uat → nonprod；prod → prod。由 app.sh 在 Pod 部署时按 `${env}` 值自动转换。

---

## 端口规划（与 K3s/Nginx 共存）

| 端口 | 服务 | 实例数 | 协议 | 跨机约束 |
|------|------|--------|------|---------|
| 53 | dnsmasq | global × 1 | UDP/TCP | 与各服务可同机；防火墙仅允许局域网 |
| 5380 | dnsmasq Web UI | global × 1 | HTTP | 与 dnsmasq 同机 |
| 80 | infra-nginx HTTP | global × 1 | HTTP | host 网络，必须与 Harbor（让出 :80 → :8880）跨机 |
| 80 / 443 | edge-nginx | DMZ × 2 | HTTPS | host 网络，独立 DMZ 节点；nonprod / prod 互相隔离 |
| 2222 | infra-nginx TCP 透传 | global | TCP | 必须与 GitLab（宿主机 :2222→:22）跨机 |
| 8082 | infra-nginx TCP 透传 | global | TCP | 必须与 Nexus（宿主机 :8082→:8082）跨机 |
| 8888 | OTel Collector self / edge-nginx 健康检查 | × 2 | HTTP | 同号但跨机不冲突；建议跨机部署 |
| 14317 / 14318 | Tempo OTLP（宿主机映射） | × 2 | gRPC/HTTP | 容器内仍是 4317/4318，避免与同机 OTel Collector 冲突 |

> 完整端口注册表（含所有 Exporter / 中间件 / Apollo / K3s）见 [架构蓝图附录 A](../architecture-blueprint.md#附录-a技术栈版本清单) 和 [配置参考](configuration-reference.md)。

---

## 流量路径速查

| 流量场景 | 入口 | 路径 |
|---------|------|------|
| 公网用户访问 nonprod 业务 | edge-nginx (nonprod) :443 | edge-nginx → k3s-nonprod.renew.com:8083 → Traefik Ingress → Pod |
| 公网用户访问 prod 业务 | edge-nginx (prod) :443 | edge-nginx → k3s-prod.renew.com:8083 → Traefik Ingress → Pod |
| 内网用户访问 nonprod 业务 | infra-nginx :80 | infra-nginx → k3s-nonprod.renew.com:8083 → Traefik → Pod |
| 内网用户访问 prod 业务 | infra-nginx :80 | infra-nginx → k3s-prod.renew.com:8083 → Traefik → Pod |
| 浏览器访问内部 UI | infra-nginx :80 | 按 server_name 反代到对应服务（GitLab/Grafana/Apollo 等） |
| Pod 访问中间件 | 直连，不经过 Nginx | CoreDNS → dnsmasq → hosts.lan → 直连数据端口 |
| Pod 访问 OTel Collector | 直连 | CoreDNS → dnsmasq → otel-{nonprod\|prod}.renew.com:4317 |
| Loki ruler 推送告警 | 直连 | DNS 解析 → alertmanager-{nonprod\|prod}.renew.com:9093 |
| GitLab SSH 克隆 | infra-nginx stream | `ssh -p 2222 git@gitlab.renew.com` → infra-nginx :2222 → GitLab :22 |
| Docker push 镜像到 Nexus | infra-nginx stream | `docker push nexus.renew.com:8082/...` → infra-nginx :8082 → Nexus :8082 |
| Docker push 镜像到 Harbor | HTTP 反代 | `docker push harbor.renew.com/...` → infra-nginx :80 → Harbor :8880 |

---

## 相关文档

- [k3s-routing-guide.md](k3s-routing-guide.md) — K3s 资源协作详解（Deployment/Pod/Service/IngressRoute/Traefik 角色比喻 + 完整路由链路）
- [observability-pipeline.md](observability-pipeline.md) — 可观测性数据流（OTel→Tempo/Loki/Prometheus）
- [configuration-reference.md](configuration-reference.md) — 跨节点连接清单与环境变量全表
- [架构蓝图第三部分](../architecture-blueprint.md) — 域名分类体系最终权威
