# K3s 资源协作与请求路由

> **本文档定位**：详解 nginx / svclb / Traefik / Ingress / Service / Endpoints / Pod 在 K3s 中如何协作完成一次请求路由（从外部域名到业务 Pod 的完整入站链路）。
> 适合 K3s 新人理解 K8s 抽象层。本项目网络架构与四层域名规范见 [network-architecture.md](network-architecture.md)。

---

## 完整请求链路（公网用户访问业务 Pod）

当用户访问 `https://demo.fat.web.renew.com` 时，整个 K3s 的协作过程如下：

### 第一阶段：寻找入口（DNS）

```
用户浏览器
    │
    │  发起 HTTPS 请求
    │
    ▼
DNS 解析
    │
    │  公网用户  → 公网 DNS A 记录       → 非生产 DMZ 公网 IP
    │  内网用户  → dnsmasq 泛解析         → infra-nginx IP
    │
    ▼
edge-nginx (DMZ) :443  /  infra-nginx :80
```

### 第二阶段：网关分流（nginx，按域名粗分流）

nginx 是 L7 HTTP 反代，按**域名（server_name）粗分流**：只决定流量进哪个 K3s 集群（nonprod / prod），不决定具体业务应用。

```
edge-nginx（公网 / DMZ）/ infra-nginx（内网）
    │
    │  1. SSL 终结：edge-nginx :443（:80 自动 301 跳 :443）；infra-nginx :80 内网明文
    │  2. server_name 正则匹配域名中的环境段，粗分流到对应 K3s 集群：
    │       ~^[a-z0-9-]+\.(dev|sit|fat|uat)\.(web|api)\.renew\.com$ → 非生产 K3s
    │       ~^[a-z0-9-]+\.prod\.(web|api)\.renew\.com$              → 生产 K3s
    │  3. proxy_pass 到 K3s 节点宿主机 :8083
    │       edge-nginx ：upstream（域名 k3s-{nonprod|prod}.renew.com:8083）
    │       infra-nginx：${K3S_{NONPROD|PROD}_TRAEFIK_HOST}:8083（必须真实 IP，见第三阶段）
    │  4. ★ proxy_set_header Host $host —— 原样透传业务域名
    │
    ▼
K3s 节点宿主机 :8083
```

> **★ Host 头是整条链路的命门**：proxy_pass 目标是集群地址（如 k3s-nonprod.renew.com），若不显式 `Host $host`，Traefik 收到的 Host 会变成集群地址而非业务域名 `demo.fat.web.renew.com`，导致匹配不到任何 Ingress 规则、返回 404。
> **域名被用两次**：nginx 用环境段（`.fat.` / `.prod.`）粗分流到集群，Traefik（第四阶段）用完整域名细路由到应用。

### 第三阶段：接入集群（svclb，K3s 内置 ServiceLB）

宿主机 `:8083` 由 K3s 的 **svclb（ServiceLB / klipper-lb）** 监听——它是裸机环境下 `type: LoadBalancer` Service 的实现，充当"云负载均衡器替身"。

```
K3s 节点宿主机 :8083
    │
    │  Traefik 的 Service 是 type: LoadBalancer，K3s 自动起一个 svclb-traefik
    │  DaemonSet：用 hostPort 在节点物理网卡占住 :8083，并通过 iptables DNAT
    │  把流量导入 Traefik Pod
    │
    ▼  iptables DNAT：节点IP:8083 → Traefik Service → Traefik Pod
Traefik Pod :8000
```

> **为什么 nginx 必须指向 K3s 节点真实 IP，不能 127.0.0.1**：svclb 的 DNAT 规则只在节点物理网卡的流量路径上生效，loopback 不命中，`127.0.0.1:8083` 会返回 502。
> svclb 是 L4 端口搬运工，不解析 HTTP、不看域名——域名路由是它身后的 Traefik 干的。

### 第四阶段：细路由（Host → Ingress → Endpoints → Pod IP）

Traefik 按 Host 头精确路由到业务应用。这是一次"三级跳"，每级查不同的表：

```
Traefik Pod :8000，收到请求  Host: demo.fat.web.renew.com
    │
    │  ① 查 Ingress：哪条规则的 host 匹配？
    │     Ingress 只存「(host + path) → (service 名 + 端口)」，到 service 名为止
    │     命中 → backend service: demo-frontend:80
    ▼
    │  ② 拿 service 名查 Endpoints（Service 按 selector 自动维护的健康 Pod 名册）
    │     Traefik watch Endpoints，Pod 增删 / 就绪变化即时刷新
    ▼
Endpoints(demo-frontend): [10.42.0.5:80, 10.42.0.6:80]   ← 真实 Pod IP（10.42 网段）
    │
    │  ③ Traefik 内部负载均衡（默认 round-robin）选一个
    ▼
直连 Pod IP（跳过 Service ClusterIP）
```

> **Ingress 管"域名找服务"，Endpoints 管"服务找 Pod"，两张表接力**：Ingress 只到 service 名（稳定），具体 Pod IP（10.42，易变）由 service 的 Endpoints 实时提供。Pod 滚动更新 / 扩缩容时 Ingress 规则不动，只有 Endpoints 名册刷新。

### 第五阶段：流量落地（Pod）

```
Traefik 选定 Pod IP（如 10.42.0.5:80）
    │
    │  flannel 负责把数据包送达目标 Pod
    │  （单节点同机走 cni0 网桥；跨节点走 flannel.1 VXLAN 封包）
    │
    ▼
Pod (demo-frontend-xxx)
    │
    │  业务代码（Nginx + Vue SPA / Spring Boot）处理请求
    │
    ▼
返回响应 → Traefik → nginx → 用户浏览器
```

---

## K3s 核心资源角色

| 资源 | 比喻 | 职责 |
|------|------|------|
| **Deployment** | 后台工头 | 创建 Pod 并监控其健康状态，确保副本数符合预期；触发滚动更新 |
| **Pod** | 苦力 | 真正运行业务代码的进程容器，本项目中是 Spring Boot / Nginx / Vue 等 |
| **Service** | 部门编制 | 用 selector 定义"哪些 Pod 属于我"，据此自动派生 Endpoints；其 ClusterIP 仅供集群内东西向访问，入站链路被 Traefik 跳过 |
| **Endpoints** | 在岗名册 | 由 Service 按 selector 自动维护的"当前健康 Pod IP 列表"（10.42 网段真实 IP），Traefik watch 此列表 |
| **Ingress** | 路由说明书 | 定义 `(host + path) → (service 名 + 端口)` 的映射规则，只到 service 名，不含 Pod IP |
| **svclb** | 门口总闸 | K3s 内置 ServiceLB，用 hostPort + iptables DNAT 把 `type: LoadBalancer` 的 Traefik 暴露到节点 `:8083` |
| **Traefik** | K3s 大门卫 | 读取 Ingress 规则，按 Host 头查到 service 名 → 查 Endpoints → 直连 Pod（跳过 ClusterIP） |

```
用户请求  https://demo.fat.web.renew.com
                       │
                       ▼
┌────────────────────────────────────────────┐
│  nginx (edge-nginx / infra-nginx)          │
│  L7 反代: server_name 按环境段粗分流       │
│  透传 Host 头: proxy_set_header Host $host │
└────────────────────────────────────────────┘
                       │  proxy_pass -> 节点IP:8083
                       ▼
┌────────────────────────────────────────────┐
│  svclb (ServiceLB / klipper-lb)            │
│  L4 端口搬运: hostPort + iptables DNAT     │
│  节点IP:8083  ->  Traefik Pod:8000         │
└────────────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────┐
│  Traefik (Ingress Controller) Pod :8000    │
│  收到请求 Host: demo.fat.web.renew.com     │
└────────────────────────────────────────────┘
                       │  ① 查 Ingress 表
                       ▼
┌────────────────────────────────────────────┐
│  Ingress (kind: networking.k8s.io/v1)      │
│  rules.host: demo.fat.web.renew.com        │
│  backend.service.name: demo-frontend       │
│  backend.service.port: 80                  │
│  (只到 service 名, 不含 Pod IP)            │
└────────────────────────────────────────────┘
                       │  ② 用 service 名查 Endpoints
                       ▼
┌────────────────────────────────────────────┐
│  Endpoints: demo-frontend                  │
│  [10.42.0.5:80, 10.42.0.6:80]              │
│  真实 Pod IP (10.42 网段)                  │
│  由 Service 按 selector 自动维护           │
└────────────────────────────────────────────┘
                       │  ③ round-robin 选一个, 跳过 ClusterIP
                       ▼  flannel 送包
┌────────────────────────────────────────────┐
│  Pod: demo-frontend-xxx                    │
│  IP: 10.42.0.5:80                          │
│  业务容器处理请求 -> 返回响应              │
└────────────────────────────────────────────┘
                       │
                       ▼
返回响应 -> Traefik -> nginx -> 用户浏览器
```

> **关键理解**：
> - **Host 头是命门**：nginx `proxy_set_header Host $host` 把业务域名原样透传，Traefik 才能按 Host 匹配 Ingress；否则 Host 变成集群地址，匹配不到规则 → 404。
> - **域名用两次**：nginx 用环境段（`.fat.` / `.prod.`）粗分流到集群，Traefik 用完整域名细路由到应用。
> - **Traefik 跳过 ClusterIP**：直接从 Endpoints 取健康 Pod IP（10.42 网段）自行负载均衡，省去"Service ClusterIP → kube-proxy → Pod"一跳。
> - **必须用 K3s 节点真实 IP**：svclb 的 DNAT 规则不在 loopback 生效，nginx 指向 `127.0.0.1:8083` 会 502。

---

## 请求落地后：业务 Pod 如何访问基础设施

业务 Pod 内部执行业务逻辑时，需要访问基础设施（MySQL / Redis / Consul / Apollo / OTel Collector 等）。本项目采用 **DNS 直连** 原则：

```
┌──────────────────────────────────────────────────────────────────────────┐
│   业务 Pod（fat 环境示例）                                                 │
│                                                                          │
│   环境变量配置（由 setup-gitlab-runner 的 app.sh 注入）:                  │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │ SPRING_DATASOURCE_URL: jdbc:mysql://mysql-fat.renew.com:3306/... │  │
│   │ SPRING_DATA_REDIS_HOST: redis-fat.renew.com                      │  │
│   │ SPRING_CLOUD_CONSUL_HOST: consul-fat.renew.com                   │  │
│   │ APOLLO_META: http://apollo-config-fat.renew.com                  │  │
│   │ OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-nonprod.renew.com:4317  │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│   解析链路:                                                               │
│     Pod → K3s CoreDNS → forward .renew.com 到 dnsmasq → hosts.lan 返回 IP │
│     Pod 拿到 IP 后直连，不再经过任何 DNS / Nginx                           │
└──────────────────────────────────────────────────────────────────────────┘
```

> **核心原则**：所有微服务 → 基础设施直接通过 `*.renew.com` 域名 DNS 直连。CoreDNS 转发链路、四层域名规范详见 [network-architecture.md](network-architecture.md)。

---

## 相关文档

- [network-architecture.md](network-architecture.md) — 本项目网络架构（四层域名规范、双入口流量路径、CoreDNS 转发）
- [observability-pipeline.md](observability-pipeline.md) — 可观测性数据流（业务 Pod 推送 Traces/Logs / Prometheus 拉取 Metrics）
- [setup-gitlab-runner/references/app-sh-spec.md](../setup-gitlab-runner/references/app-sh-spec.md) — app.sh 生成的 K8s 资源结构（Deployment/HPA/PDB/Service/Ingress/PVC）
- [request-lifecycle.md](request-lifecycle.md) — 端到端请求案例
