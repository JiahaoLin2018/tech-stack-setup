# 请求生命周期 — 以"用户申请贷款"为例（多环境视角）

> **本文档定位**：通过真实业务场景，展示一个 HTTP 请求如何穿越整个技术栈，并体现多环境隔离架构下数据流如何按 env 分流。
> 适合新人入门、理解服务间协作。

---

## 场景描述

用户张三在手机 APP 上点击"申请贷款"，填写金额 50000 元，提交申请到 **PROD 环境**。

后端需要完成：

1. 验证用户身份，查询用户信息
2. 风控评估（调用风控引擎）
3. 创建贷款申请记录
4. 异步通知审批人员

---

## 多环境视角：同一请求在不同环境的链路差异

| 环境 | 公网入口 | K3s 集群 | 中间件直连域名 | OTel 推送目标 | Apollo Meta |
|------|---------|---------|--------------|--------------|-------------|
| dev / sit / fat / uat | edge-nginx (nonprod) :443 | k3s-nonprod.renew.com:8083 | `mysql-{env}.renew.com` 等 | `otel-nonprod.renew.com:4317` | `apollo-config-{env}.renew.com` |
| **prod** | **edge-nginx (prod) :443**（独立 DMZ + 独立公网 IP + 物理孤岛）| **k3s-prod.renew.com:8083** | `mysql-prod.renew.com` 等 | `otel-prod.renew.com:4317` | `apollo-config-prod.renew.com` |

> 下面以 **PROD 环境**为例追踪完整链路；nonprod 4 环境逻辑完全相同，只是中间件 / OTel / Apollo / K3s 全部走对应环境的域名。

---

## 完整请求流（PROD 环境）

```
                        ① 用户提交贷款申请
                              │
                              ▼  https://app.prod.api.renew.com/api/loan/apply
┌─────────────────────────────────────────────────────────────────┐
│           公网 DNS A 记录 → 生产 DMZ 公网 IP                       │
│           edge-nginx (prod) :443                                 │
│             - SSL 终结（HTTPS → HTTP）                            │
│             - 限流 / IP 白名单（按域名精确控制）                   │
│             - HTTP :80 强制 301 → HTTPS :443                     │
│             - proxy_pass → k3s-prod.renew.com:8083              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    生产 K3s 集群                                  │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │           K3s Traefik Ingress :8083                     │    │
│  │  路由 Host=app.prod.api.renew.com → gateway Service      │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │            Gateway (网关) Pod (Namespace: prod)          │    │
│  │  ← Consul 查询: consul-prod.renew.com:8500               │    │
│  │      发现 loan-service 健康实例（仅含 metrics tag 的服务）│    │
│  │  → 负载均衡转发到 loan-service:8080                       │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│      loan-service Pod (env=prod，由 app.sh 部署，Namespace: prod) │
│                                                                   │
│  环境变量（app.sh 注入）:                                          │
│    OTEL_RESOURCE_ATTRIBUTES: deployment.environment=prod,...      │
│    OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-prod.renew.com:4317  │
│    OTEL_METRICS_EXPORTER: none                                   │
│    SPRING_PROFILES_ACTIVE: prod                                  │
│                                                                   │
│  ② Apollo 读取配置                                                │
│     -Dapollo.meta=http://apollo-config-prod.renew.com             │
│     → 拉取最大贷款额度、利率表、风控开关等                          │
│                                                                   │
│  ③ 验证用户 — 查 MySQL                                             │
│     SELECT * FROM users WHERE id=?                               │
│     → mysql-prod.renew.com:3306（生产专用实例，物理隔离）          │
│                                                                   │
│  ④ 检查缓存 — 查 Redis                                             │
│     GET user:credit_score:张三                                   │
│     → redis-prod.renew.com:6379（ACL `app` 用户连接）              │
│     命中 → 直接使用缓存                                           │
│     未命中 → 查 MySQL 后 SET 到 Redis（TTL 30min）                │
│                                                                   │
│  ⑤ RPC 调用风控服务                                                 │
│     ← Consul (consul-prod.renew.com:8500) 查询 risk-service       │
│     → HTTP 调用 risk-service:8081/api/evaluate                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              risk-service Pod (env=prod, Namespace: prod)        │
│                                                                   │
│  ⑥ 查询风控规则文档 — MongoDB                                      │
│     db.risk_rules.find({product: "loan"})                        │
│     → mongodb-prod.renew.com:27017                               │
│       （启用 security.authorization，app 用户 readWrite + dbAdmin）│
│                                                                   │
│  ⑦ 执行规则引擎                                                    │
│     输入：用户信息 + 信用分 + 规则集合                                │
│     输出：{approved: true, score: 85, limit: 50000}               │
│                                                                   │
│  → 返回评估结果给 loan-service                                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   loan-service (继续处理)                          │
│                                                                   │
│  ⑧ 写入贷款申请 — MySQL                                           │
│     INSERT INTO loan_applications (...)                          │
│     → mysql-prod.renew.com:3306（事务，同时更新在途申请数）         │
│                                                                   │
│  ⑨ 发送异步消息 — RabbitMQ                                         │
│     发布到 exchange: loan.events, routing_key: loan.created      │
│     → rabbitmq-prod.renew.com:5672                               │
│       （Quorum Queue，业务声明 x-queue-type: quorum）              │
│                                                                   │
│  ⑩ 返回 HTTP 200                                                   │
│     {"status": "PENDING", "applicationId": "LA-20260427-001"}     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ (异步消费)
┌─────────────────────────────────────────────────────────────────┐
│                 notify-service Pod (env=prod)                     │
│                                                                   │
│  ⑪ 消费 RabbitMQ 消息                                             │
│     订阅 queue: loan.notification                                 │
│     binding: loan.created                                         │
│                                                                   │
│  ⑫ 发送通知                                                       │
│     → 钉钉 Webhook: 通知审批人员                                    │
│     → 短信网关: 通知用户 "申请已提交"                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 同一过程，可观测性层在做什么？

**从用户点击到返回结果的这 200ms 内，以下数据被自动采集到生产 LGT 栈：**

```
loan-service / risk-service / notify-service (env=prod)
    │
    │  方案 A（SB 3.x）: Micrometer Tracing + OTel Bridge
    │  方案 B（SB 2.x）: OTel Java Agent（jar 由 setup-gitlab-runner 挂载）
    │  无论哪种方案，都通过 OTLP 推送 Traces / Logs；Metrics 走 /actuator/prometheus
    │
    │  env 标签由 OTEL_RESOURCE_ATTRIBUTES=deployment.environment=prod 携带
    ↓
┌────────────────────────────────────────────────────────────────┐
│           OTel Collector (prod) :4317                            │
│           部署位置: 生产 LGT 节点（与 nonprod 完全独立）           │
│  接收 OTLP 数据 → 根据数据类型路由到不同后端                        │
│                                                                  │
│  Traces ──► tempo-prod.renew.com:14317                           │
│             存储完整调用链：                                        │
│               Gateway → loan-service → risk-service              │
│                            ↓ MySQL    ↓ MongoDB                  │
│             每个 Span: 耗时、状态码、SQL 语句                       │
│             保留 deployment.environment=prod 属性                 │
│                                                                  │
│  Logs   ──► loki-prod.renew.com:3100/otlp                        │
│             存储结构化日志（JSON 格式）：                              │
│             {"traceId":"abc123", "level":"INFO",                  │
│              "msg":"贷款申请创建成功", "userId":"张三"}              │
│             自动索引为 deployment_environment=prod 标签             │
│             生产 Loki 启用 LOKI_AUTH_ENABLED=true（多租户认证）     │
└────────────────────────────────────────────────────────────────┘

    同时 Prometheus (prod) 主动拉取：
┌────────────────────────────────────────────────────────────────┐
│           Prometheus (prod) :9090                                │
│           部署位置: 生产 LGT 节点                                  │
│                                                                  │
│  spring-boot consul_sd:                                          │
│    consul-prod.renew.com:8500，仅含 metrics tag 的服务            │
│    → loan-service:8080/actuator/prometheus                       │
│    → risk-service:8081/actuator/prometheus                       │
│    relabel: target_label env replacement prod                    │
│                                                                  │
│  static jobs:                                                    │
│    mysql-prod.renew.com:9104 / redis-prod.renew.com:9121 等       │
│    otel-prod.renew.com:8888 / tempo-prod.renew.com:3200 等        │
│    alertmanager-prod.renew.com:9093                              │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│           Grafana (prod) :3000                                   │
│           Web UI: https://grafana-prod-ui.renew.com              │
│                                                                  │
│  运维人员（生产专属看板）:                                          │
│                                                                  │
│  📊 Metrics Dashboard (env=prod 默认过滤)                          │
│  ├── loan-service QPS: 120 req/s                                 │
│  ├── P99 延迟: 180ms                                              │
│  ├── risk-service 平均耗时: 45ms                                   │
│  └── MySQL 连接池使用率: 60%                                       │
│                                                                  │
│  🔍 Trace 详情（Tempo TraceQL）:                                   │
│  {resource.deployment.environment="prod" && duration>500ms}      │
│  ├── Gateway: 2ms                                                │
│  ├── loan-service: 150ms                                         │
│  │   ├── MySQL SELECT: 5ms                                       │
│  │   ├── Redis GET: 0.3ms (cache hit)                            │
│  │   ├── risk-service RPC: 120ms  ← 瓶颈在这里                   │
│  │   │   ├── MongoDB query: 80ms  ← 慢查询                       │
│  │   │   └── 规则引擎计算: 40ms                                    │
│  │   └── MySQL INSERT: 8ms                                       │
│  └── RabbitMQ publish: 1ms                                       │
│                                                                  │
│  📝 Loki 关联日志（LogQL）:                                         │
│  {deployment_environment="prod", service_name="risk-service"}    │
│   | json | traceId="abc123"                                      │
│  └── 通过 traceId 关联，看到该请求的所有日志                          │
│                                                                  │
│  ⚠️ Prometheus 告警规则触发                                         │
│  → Alertmanager (prod) :9093                                     │
│    "risk-service env=prod MongoDB P99 查询延迟 > 100ms，持续 5 分钟" │
│  → 钉钉群通知                                                       │
└────────────────────────────────────────────────────────────────┘
```

---

## nonprod vs prod 数据隔离演示

同样的请求若发生在 **FAT 环境**（用户测试），数据流如下：

| 阶段 | FAT 环境 | PROD 环境 |
|------|---------|----------|
| 公网入口 | `edge-nginx (nonprod)` | `edge-nginx (prod)`（独立公网 IP / 物理孤岛） |
| K3s 集群 | nonprod 集群 Namespace=fat | prod 集群（物理孤岛） |
| 数据库 | `mysql-fat.renew.com:3306` | `mysql-prod.renew.com:3306` |
| 缓存 | `redis-fat.renew.com:6379` | `redis-prod.renew.com:6379` |
| 文档库 | `mongodb-fat.renew.com:27017` | `mongodb-prod.renew.com:27017` |
| 消息队列 | `rabbitmq-fat.renew.com:5672` | `rabbitmq-prod.renew.com:5672` |
| 服务发现 | `consul-fat.renew.com:8500` | `consul-prod.renew.com:8500` |
| Apollo Meta | `apollo-config-fat.renew.com` | `apollo-config-prod.renew.com` |
| OTel Collector | `otel-nonprod.renew.com:4317` | `otel-prod.renew.com:4317` |
| LGT 栈 | nonprod 一套（4 环境共用，env 标签隔离） | prod 一套（独立物理） |
| Grafana 查询 | `grafana-nonprod-ui.renew.com`，$env=fat 过滤 | `grafana-prod-ui.renew.com` |
| 数据可见性 | 4 环境共用 LGT，通过 `env`/`deployment_environment` 标签隔离查询 | 完全独立 LGT，无任何数据交集 |

> **关键**：nonprod 环境（dev/sit/fat/uat）共用 1 套 LGT 栈和 1 个 K3s 集群，通过 K8s Namespace + env 标签实现逻辑隔离；prod 环境物理孤岛，与 nonprod 无任何硬件 / 网络 / 数据交集。

---

## 服务参与总结

| 步骤 | 涉及的基础设施 | 作用 | 多环境隔离方式 |
|------|--------------|------|--------------|
| 接入层 | **edge-nginx (DMZ 双实例)** | SSL 终结、IP 白名单、限流，统一入口转发到对应 K3s | nonprod / prod 独立公网 IP / 独立机房 |
| 服务发现 | **Consul × 5** | 微服务通过 Consul 找到下游实例 | 5 套环境完全独立物理实例 |
| 读取配置 | **Apollo Portal + Config × 5** | 启动和运行时获取业务配置 | Portal 全局唯一；Config × 5 独立；prod MySQL 物理隔离 |
| 用户查询 | **MySQL × 5** | 关系数据存储 | 5 套独立物理实例（与 Apollo MySQL 完全分离）|
| 缓存加速 | **Redis × 5** | 亚毫秒级读取、分布式锁 | 5 套独立实例；ACL `app` 用户 |
| 规则查询 | **MongoDB × 5** | 灵活 Schema 文档存储 | 5 套独立实例；启用认证 |
| 异步通知 | **RabbitMQ × 5** | 服务间异步通信 | 5 套独立实例；Quorum Queue |
| 链路追踪 | **OTel Collector → Tempo × 2** | 记录完整调用链 | nonprod 共用 + prod 独立；env 标签注入 |
| 日志聚合 | **OTel Collector → Loki × 2** | 结构化日志带 traceId | 同上；deployment_environment 标签 |
| 指标监控 | **Prometheus × 2** | QPS / 延迟 / JVM 指标 | nonprod 采集 4 套环境 + prod 采集 1 套；env 标签 relabel |
| 统一看板 | **Grafana × 2** | Trace↔Log↔Metrics 关联跳转 | nonprod / prod 独立看板；$env 模板变量过滤 |
| 告警通知 | **Alertmanager × 2** | 钉钉群 / 邮件 | nonprod / prod 独立 Alertmanager（同 Compose）|

---

## 关键设计点

### 为什么用三个数据库？

```
MySQL   → 强一致性、事务保证 → 用户表、订单表、金融流水
Redis   → 亚毫秒延迟、原子操作 → 缓存、分布式锁、限流计数器
MongoDB → 灵活 Schema、复杂文档 → 风控规则、审批流程、操作日志归档
```

按数据特性选择最合适的存储引擎，而不是"什么都存 MySQL"。

### 为什么同步调用 + 异步消息混用？

```
同步（HTTP/RPC）：  loan → risk  （必须等结果，才能决定是否通过）
异步（RabbitMQ）：  loan → notify（发通知不影响主流程，失败可重试）
```

原则：**影响用户响应的调用走同步，不影响的走异步**。

### 为什么 OTel Collector 是中间层？

```
不好的做法：  App → Tempo     （每个后端一个配置，耦合）
             App → Loki
             App → Prometheus

好的做法：    App → OTel Collector → Tempo / Loki / Prometheus
```

OTel Collector 作为统一网关：

- 应用只需对接一个 OTLP 端点（`otel-{nonprod|prod}.renew.com:4317`），不关心后端
- 后端切换（Tempo → Jaeger）不需要改应用代码
- 可以在 Collector 层做采样、过滤、env 兜底插入

### 为什么 Metrics 不走 OTLP？

```
强制设置：OTEL_METRICS_EXPORTER=none（方案 B 还加 OTEL_INSTRUMENTATION_MICROMETER_ENABLED=false）

原因:
  1. Metrics 是状态型数据，Pull 模式更可靠（应用 OOM 重启不丢数据）
  2. Micrometer 已成熟产出 /actuator/prometheus，OTLP 重复导出会产生指标重复
  3. Prometheus consul_sd 能自动发现服务实例，无需 Collector 中转
  4. PromQL 与告警规则在 Pull 模式下更直接
```

### 为什么 nonprod 4 环境共用 1 套 LGT？

```
设计权衡：
  ✅ 节省资源（4 套 LGT × 4 环境 = 16 实例 → 4 实例）
  ✅ 通过 OTEL_RESOURCE_ATTRIBUTES + relabel 实现 env 标签逻辑隔离
  ✅ Grafana $env 模板变量切换，体验上和独立部署无差异
  ❌ 不适用于生产：prod 物理孤岛，独立 1 套 LGT 保证审计和合规
```

---

## 相关文档

- [observability-pipeline.md](observability-pipeline.md) — 三支柱完整数据流 + 双方案接入
- [network-architecture.md](network-architecture.md) — DNS 解析机制 + 双入口流量
- [k3s-routing-guide.md](k3s-routing-guide.md) — K3s Traefik 如何路由到 Pod
- [setup-cicd/actions/integrate.md](../setup-cicd/actions/integrate.md) — Spring Boot 接入完整示例
