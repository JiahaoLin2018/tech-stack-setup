# 可观测性数据流 — Metrics / Traces / Logs 三支柱

> **本文档定位**：详解可观测性 6 个组件如何协作实现 Metrics / Traces / Logs 三支柱采集；env 标签注入主通路；nonprod / prod 双栈数据流；Spring Boot 双方案接入。
>
> 架构权威：[architecture-blueprint.md](../architecture-blueprint.md) 第二、四部分。Spring Boot 详细接入示例：[setup-cicd/actions/integrate.md](../setup-cicd/actions/integrate.md)。

---

## 数据流总览

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Spring Boot 应用（业务 Pod）                              │
├─────────────────────────────────────────────────────────────────────────────┤
│  Traces ──OTLP──► otel-{nonprod|prod}.renew.com:4317 ──► Tempo:14317        │
│  Logs   ──OTLP──► otel-{nonprod|prod}.renew.com:4317 ──► Loki:3100/otlp     │
│  Metrics ───────► /actuator/prometheus                                      │
│                         ↓                                                   │
│              Prometheus 直接拉取（Consul consul_sd 服务发现）                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

> **核心设计**：Metrics 与 Traces/Logs 走**两条独立通路**。Metrics 由 Prometheus 拉取 `/actuator/prometheus`（Micrometer 产出）；Traces/Logs 由 OTel SDK / Java Agent 推送到 Collector。两条通路完全解耦，互不干扰，**不会产生重复指标**（业务 Pod 强制 `OTEL_METRICS_EXPORTER=none`）。

---

## 整体数据流（nonprod 实例为例）

```
                K3s Pod (Spring Boot 微服务，env=fat 示例)
               ┌─────────────────────────────────────┐
               │  ┌────────────────────────────┐     │
               │  │  方案 A（主力，SB 3.x）     │     │
               │  │  Micrometer Tracing        │     │
               │  │  + OTel Bridge             │     │
               │  │  + Logback OTLP Appender   │     │
               │  └────────────────────────────┘     │
               │  ┌────────────────────────────┐     │
               │  │  方案 B（兜底，SB 2.x）     │     │
               │  │  OTel Java Agent           │     │
               │  │  （字节码注入，挂载 jar）    │     │
               │  └────────────────────────────┘     │
               │                                     │
               │  Micrometer Prometheus              │
               │  （两方案共用的指标通路）            │
               │  → /actuator/prometheus             │
               └──────────────┬──────────────────────┘
                              │
                              │ OTel SDK / Agent 推送
                              │ DNS 解析 otel-nonprod.renew.com（hosts.lan 直连）
                              │ OTLP（gRPC :4317 或 HTTP :4318）
                              ↓
              ┌──────────────────────────────────┐
              │     OTel Collector (nonprod)      │
              │     部署目录: /opt/tech-stack/     │
              │       otel-collector-nonprod/     │
              │                                   │
              │  receivers:                       │
              │    otlp (gRPC :4317 / HTTP :4318) │
              │                                   │
              │  processors:                      │
              │    batch (批量发送)                │
              │    memory_limiter                 │
              │    resource (action: insert       │
              │      deployment.environment       │
              │      = ${DEPLOYMENT_ENV}          │
              │      兜底，上游传值不覆盖)         │
              │                                   │
              │  exporters:                       │
              │    ┌──────────────────────────┐   │
              │    │  otlp/tempo              │───┼──► tempo-nonprod.renew.com:14317  (Traces, OTLP gRPC)
              │    │  otlphttp/loki           │───┼──► loki-nonprod.renew.com:3100/otlp (Logs, OTLP HTTP)
              │    └──────────────────────────┘   │
              │  service.pipelines:               │
              │    traces / logs（无 metrics）     │
              └──────────────────────────────────┘

                   同时 Prometheus 主动拉取：
              ┌──────────────────────────────────────────────────────────────────┐
              │      Prometheus (nonprod)                                        │
              │      部署目录: /opt/tech-stack/prometheus-nonprod/               │
              │                                                                  │
              │  scrape_configs:                                                 │
              │    spring-boot-{dev,sit,fat,uat}（4 套独立 consul_sd job）       │──► 业务 Pod /actuator/prometheus
              │      → consul-{env}.renew.com:8500 服务发现                      │   labels: env={env}
              │      → 仅发现 tags: ['metrics'] 的服务                            │
              │      → relabel: target_label env replacement {env}               │
              │                                                                  │
              │    static jobs（中间件 Exporter，按环境）:                        │
              │      mysql-{dev,sit,fat,uat}.renew.com:9104                      │
              │      redis-{dev,sit,fat,uat}.renew.com:9121                      │
              │      mongodb-{dev,sit,fat,uat}.renew.com:9216                    │
              │      rabbitmq-{dev,sit,fat,uat}.renew.com:15692                  │
              │                                                                  │
              │    static jobs（域级）:                                           │
              │      otel-nonprod.renew.com:8888（Collector 自身指标）           │
              │      tempo-nonprod.renew.com:3200（Tempo 自身）                  │
              │      loki-nonprod.renew.com:3100（Loki 自身）                    │
              │      alertmanager-nonprod.renew.com:9093                         │
              │                                                                  │
              │  alerting:                                                       │
              │    alertmanagers:                                                │──► alertmanager-nonprod.renew.com:9093
              │    rules/*.yml                                                   │
              │  --web.enable-remote-write-receiver                              │◄── tempo metrics_generator remote_write
              └──────────────────────────────────────────────────────────────────┘

                            ↓ 查询
              ┌──────────────────────────┐
              │     Grafana (nonprod)     │
              │   (统一可视化看板)         │
              │                           │
              │  数据源（envsubst 渲染）:  │
              │    Prometheus → :9090     │
              │    Tempo → :3200          │
              │    Loki → :3100           │
              │                           │
              │  关联跳转:                 │
              │    Metrics → Trace        │
              │    Trace → Log            │
              │    Log → Trace            │
              │    Trace → Service Map    │
              │  $env 模板变量贯通        │
              │  PromQL/LogQL/TraceQL     │
              └──────────────────────────┘
```

> 生产实例（`-prod`）拓扑相同，但仅采集 1 套生产服务（spring-boot consul_sd × 1 + 4 中间件 + 4 域级）。

---

## env 标签注入主通路（v1.5.0）

LGT 环境隔离的**唯一注入入口**是每个业务 Pod 的 `OTEL_RESOURCE_ATTRIBUTES`，由 `setup-gitlab-runner` 的 `app.sh` 在 `kubectl apply` 时注入：

```yaml
# K8s Deployment env 块（app.sh 自动生成）
env:
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "deployment.environment=fat,service.namespace=fat"   # ${env} 实际值
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-nonprod.renew.com:4317"                 # ${domainEnv}
  - name: OTEL_METRICS_EXPORTER
    value: "none"                                                # 强制关闭 OTLP 指标
  - name: OTEL_SERVICE_NAME
    value: "loan-service"                                        # ${appId}
```

### env 标签如何流经三支柱

```
┌─────────────────────────────────────────────────────────────────┐
│  OTEL_RESOURCE_ATTRIBUTES=deployment.environment=fat            │
│                                                                 │
│  ┌─────────────────┐                                            │
│  │  Spring Boot    │                                            │
│  │  (启动时读取)    │                                            │
│  └────────┬────────┘                                            │
│           │                                                     │
│     ┌─────┴─────┬───────────────────┐                           │
│     ▼           ▼                   ▼                           │
│  Traces      Logs               Metrics                         │
│  (OTLP)      (OTLP)            (Prometheus 拉取)                 │
│     │           │                   │                           │
│     ▼           ▼                   ▼                           │
│  Tempo        Loki              Prometheus                      │
│  resource.    otlp_config.      relabel_configs:                │
│  deployment.  resource_attrs    target_label: env               │
│  environment  → 自动转          replacement: ${env}             │
│  =fat         deployment_       （job 内固定值）                  │
│              environment 标签                                    │
│                                                                 │
│  Grafana 查询时三支柱均可按 env=fat / deployment_environment=fat 过滤  │
└─────────────────────────────────────────────────────────────────┘
```

### 各组件 env 标签实现

| 组件 | env 标签注入方式 | 标签字段名 | 查询语法示例 |
|------|---------------|-----------|------------|
| **Tempo** | OTel Resource Attribute 原生保留 | `resource.deployment.environment` | TraceQL: `{resource.deployment.environment="fat" && duration>500ms}` |
| **Loki** | `limits_config.otlp_config.resource_attributes` 自动索引 | `deployment_environment`（点号自动转下划线） | LogQL: `{deployment_environment="fat", service_name="loan-service"} \|= "ERROR"` |
| **Prometheus** | `relabel_configs` per-job 固定 `env` 标签 | `env` | PromQL: `rate(http_server_requests_seconds_count{env="fat"}[5m])` |
| **Grafana** | 模板变量 `$env` 贯通 PromQL/LogQL/TraceQL | — | Dashboard 顶部下拉选择 dev/sit/fat/uat |

---

## OTel Collector 角色与配置

### 服务管道（traces + logs，无 metrics）

```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, resource, batch]
      exporters: [otlp/tempo]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, resource, batch]
      exporters: [otlphttp/loki]
```

### resource processor（兜底注入）

```yaml
processors:
  resource:
    attributes:
      - key: deployment.environment
        value: ${DEPLOYMENT_ENV}        # 兜底值：nonprod / prod
        action: insert                   # 仅当上游未传时插入；上游传 dev/sit/fat/uat/prod 时不覆盖
```

> **DEPLOYMENT_ENV 的角色**：仅作 Collector 自身服务标识 + 上游遗漏时的兜底，**非全局覆盖**。所有业务 Pod 都通过 app.sh 注入了具体 env，因此实际数据流中 deployment.environment 始终是 dev/sit/fat/uat/prod 之一。

### 端口策略（避免与同机 Tempo 冲突）

| 服务 | 容器内端口 | 宿主机端口 |
|------|----------|-----------|
| OTel Collector OTLP gRPC | 4317 | 4317 |
| OTel Collector OTLP HTTP | 4318 | 4318 |
| OTel Collector self metrics | 8888 | 8888 |
| Tempo OTLP gRPC | 4317 | **14317**（避免冲突） |
| Tempo OTLP HTTP | 4318 | **14318** |

> 同机部署 OTel Collector 与 Tempo 时，Tempo 改用宿主机 14317/14318 端口映射；容器内仍是 4317/4318。

---

## Spring Boot 双方案接入

### 方案 A — Micrometer + OTel Bridge（SB 3.x 主力）

**适用**：Spring Boot 3.x + JDK 17+

**依赖**：

| 依赖 | 用途 |
|------|------|
| `spring-boot-starter-actuator` | 暴露 `/actuator/prometheus` |
| `micrometer-registry-prometheus` | Prometheus 指标格式 |
| `micrometer-tracing-bridge-otel` | 链路桥接到 OTel |
| `opentelemetry-exporter-otlp` | OTLP 导出 Traces |
| `opentelemetry-logback-appender-1.0` | 日志 OTLP 导出 |
| `spring-cloud-starter-consul-discovery` | Consul 服务注册（必打 `metrics` tag） |

**Apollo 配置**（`tech.common` namespace）：

```properties
ops.supportOtel = true
ops.otelMode    = bridge
ops.javaVersion = 21
```

### 方案 B — OTel Java Agent（SB 2.x 兜底）

**适用**：Spring Boot 2.x + JDK 8/11，或主动选择字节码注入方式

**依赖**：

| 依赖 | 用途 |
|------|------|
| `spring-boot-starter-actuator` | 暴露 `/actuator/prometheus` |
| `micrometer-registry-prometheus` | Prometheus 指标格式 |
| `spring-cloud-starter-consul-discovery` | Consul 服务注册 |
| **OTel Java Agent v2.26.1** | 字节码注入埋点 |

**Agent jar 来源**：

| 项 | 当前方案 |
|---|---------|
| 来源 | setup-gitlab-runner start 阶段 B 自动下载 |
| 存放位置 | 宿主机 `/opt/tech-stack/cicd/opentelemetry-javaagent.jar` |
| 注入方式 | K8s Deployment volumes 挂载到容器 `/opt/otel/opentelemetry-javaagent.jar:ro` |
| 跨 JDK 兼容 | JDK 8~21 通用 |
| 业务镜像 | **无需预置**，更新只需替换宿主机文件 |

**Apollo 配置**：

```properties
ops.supportOtel = true
ops.otelMode    = agent
ops.javaVersion = 8     # 或 11，JDK<17 时 app.sh 自动覆写为 agent
```

**额外注入**（agent 模式 app.sh 自动追加）：

```yaml
env:
  - name: OTEL_INSTRUMENTATION_MICROMETER_ENABLED
    value: "false"   # 防止 Agent 又导出指标，重复采集
  - name: JAVA_OPTS
    value: "-javaagent:/opt/otel/opentelemetry-javaagent.jar"
```

### 方案对比

| 维度 | 方案 A（Bridge） | 方案 B（Agent） |
|------|----------------|----------------|
| 链路推送 | Micrometer Tracing → OTel Bridge → OTLP | Agent 字节码注入 → OTLP |
| 日志推送 | OTel Logback Appender → OTLP | Agent 自动注入 Logback 桥接 → OTLP |
| 指标 | Micrometer Prometheus → `/actuator/prometheus` | 同左（强制 `OTEL_INSTRUMENTATION_MICROMETER_ENABLED=false`） |
| OTel 导出器关闭 | `OTEL_METRICS_EXPORTER=none` | 同左 |
| env 标签注入 | `OTEL_RESOURCE_ATTRIBUTES` Pod 级 | 同左 |
| Java 兼容 | JDK 17+（Spring Boot 3.x 要求） | JDK 8+ |
| Agent jar | 无需 | 必需，由 setup-gitlab-runner 统一管理 |

> OTel Collector / Tempo / Loki / Prometheus / Grafana 后端**完全无需区分两种方案**，两者都通过 OTLP 推送 + Prometheus 拉取，数据流完全一致。

### 关闭 OTel 的降级路径

当 `ops.supportOtel=false` 时，app.sh 不注入任何 `OTEL_*` 环境变量，也不挂载 Agent jar：

```
┌─────────────────────────────────────────────────────────────────┐
│  ops.supportOtel = false                                        │
│                                                                 │
│  数据流变化:                                                     │
│    Traces:  App ───×─── OTel Collector ───×─── Tempo  ❌ 断开    │
│    Logs:    App ───×─── OTel Collector ───×─── Loki   ❌ 断开    │
│    Metrics: App ←──── Prometheus ────────────────────  ✅ 正常   │
│                                                                 │
│  影响:                                                          │
│    ✅ Prometheus 指标正常采集                                     │
│    ❌ Grafana 无法通过 traceId 跳转                               │
│    ❌ 无链路追踪，无法分析调用链                                   │
│    ❌ 日志不进入 Loki，需登录 Pod 查看                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Loki OTLP 原生接收

Loki 3.5+ 内置 OTLP 接收器，OTel Collector 直接发送日志到 `http://loki-{nonprod|prod}.renew.com:3100/otlp`，无需定制 exporter。

```
OTel Collector                          Loki 3.5+
┌─────────────────┐                    ┌──────────────────────────┐
│ otlphttp/loki   │── OTLP/HTTP ──►    │ /otlp 端点                │
│                 │                    │                          │
│ 日志包含:        │                    │ otlp_config:             │
│  resource.attrs:│                    │   resource_attributes:   │
│   service.name  │   ─────────►       │     service.name → 标签   │
│   deployment.   │   自动转换          │     deployment.environment│
│   environment   │                    │       → deployment_       │
│  log body       │   ─────────►       │       environment 标签    │
└─────────────────┘                    └──────────────────────────┘
```

### Loki 关键配置

| 配置 | 值 | 说明 |
|------|---|------|
| `allow_structured_metadata` | `true` | 启用结构化元数据存储 |
| `otlp_config.resource_attributes` | 自动索引 OTLP resource attributes | 包括 service.name → service_name；deployment.environment → deployment_environment |
| `auth_enabled`（生产）| **`true`** | 强制多租户认证（蓝图安全加固基线） |

---

## Tempo metrics_generator → Prometheus

Tempo metrics_generator 生成 service-graph / span-metrics，通过 remote_write 写入 Prometheus，供 Grafana 生成 Service Map：

```
Tempo metrics_generator                    Prometheus
┌──────────────────────┐                    ┌──────────────────────┐
│ service-graph 指标    │── remote_write ──► │ /api/v1/write        │
│ span-metrics 指标     │                    │ （需 --web.enable-   │
│                      │                    │   remote-write-      │
│ 写入目标:             │                    │   receiver 启动参数） │
│  prometheus-          │                    │                      │
│  {nonprod|prod}.      │                    │ 写入后 Grafana 通过   │
│  renew.com:9090       │                    │ Tempo serviceMap 数据 │
│                      │                    │ 源关联到 Prometheus   │
└──────────────────────┘                    └──────────────────────┘
```

### Tempo 端口策略

| 端口 | 容器内 | 宿主机 | 用途 |
|------|-------|-------|------|
| 3200 | 3200 | 3200 | HTTP 查询 API + 自身 Metrics |
| 4317 | 4317 | **14317** | OTLP gRPC（避免与 OTel Collector 同机冲突） |
| 4318 | 4318 | **14318** | OTLP HTTP |
| 9411 | 9411 | 9411 | Zipkin 兼容 |

---

## Prometheus 抓取目标清单（nonprod 实例）

| 目标类型 | 发现方式 | 地址 | 端口 | env 标签 |
|---------|---------|------|------|---------|
| Spring Boot 微服务（dev）| consul_sd | `consul-dev.renew.com:8500`，仅含 tags: ['metrics'] | 8080 | `dev` |
| Spring Boot 微服务（sit）| consul_sd | `consul-sit.renew.com:8500` | 8080 | `sit` |
| Spring Boot 微服务（fat）| consul_sd | `consul-fat.renew.com:8500` | 8080 | `fat` |
| Spring Boot 微服务（uat）| consul_sd | `consul-uat.renew.com:8500` | 8080 | `uat` |
| Prometheus 自身 | static | localhost | 9090 | — |
| OTel Collector | static | `otel-nonprod.renew.com` | 8888 | `nonprod` |
| Loki | static | `loki-nonprod.renew.com` | 3100 | `nonprod` |
| Tempo | static | `tempo-nonprod.renew.com` | 3200 | `nonprod` |
| Alertmanager | static | `alertmanager-nonprod.renew.com` | 9093 | `nonprod` |
| MySQL Exporter × 4 | static | `mysql-{dev,sit,fat,uat}.renew.com` | 9104 | `{env}` |
| Redis Exporter × 4 | static | `redis-{dev,sit,fat,uat}.renew.com` | 9121 | `{env}` |
| MongoDB Exporter × 4 | static | `mongodb-{dev,sit,fat,uat}.renew.com` | 9216 | `{env}` |
| RabbitMQ Prometheus 插件 × 4 | static | `rabbitmq-{dev,sit,fat,uat}.renew.com` | 15692 | `{env}` |

> **生产实例**（`-prod`）：1 套 spring-boot consul_sd（`consul-prod.renew.com`）+ 4 中间件 Exporter（`{svc}-prod.renew.com`）+ 4 域级（`otel-prod` / `loki-prod` / `tempo-prod` / `alertmanager-prod`）。

---

## 推送 vs 拉取

| 模式 | 数据类型 | 来源 | 接收方 |
|------|---------|------|-------|
| **推送 Push** | Traces | 业务 Pod (OTel SDK / Agent) | OTel Collector :4317/:4318 → Tempo :14317 |
| **推送 Push** | Logs | 业务 Pod (OTel SDK / Agent) | OTel Collector :4317/:4318 → Loki :3100/otlp |
| **推送 Push** | Service Graph 指标 | Tempo metrics_generator | Prometheus :9090 (remote_write) |
| **推送 Push** | 告警 | Loki ruler / Prometheus alerting | Alertmanager :9093 |
| **拉取 Pull** | Metrics（业务）| Prometheus consul_sd 自动发现 | 业务 Pod `/actuator/prometheus` |
| **拉取 Pull** | Metrics（中间件）| Prometheus static_configs | Exporter `/metrics`（mysql:9104 等）/ RabbitMQ 插件 :15692 |
| **拉取 Pull** | Metrics（LGT 自身）| Prometheus static_configs | OTel Collector :8888 / Tempo :3200 / Loki :3100 / Alertmanager :9093 |

**两种模式并存**的原因：

- Traces / Logs 是**事件型**数据，必须由应用主动推送（Pull 模式无法获取已结束的请求）
- Metrics 是**状态型**数据，Prometheus 定时拉取更可靠（不依赖应用推送能力，应用 OOM 重启不丢数据）

---

## 数据关联：Metrics ↔ Traces ↔ Logs

三种数据通过 **traceId** 和 **service / env 标签** 关联，在 Grafana 中实现一键跳转：

```
Grafana Metrics Dashboard
│
│  发现 loan-service P99 延迟飙升到 500ms (env=fat)
│  点击 "Exemplar" 链接（Prometheus 记录的采样 traceId）
│
├──► Grafana Tempo (Trace 详情)
│    │
│    │  TraceQL: {resource.deployment.environment="fat" && resource.service.name="loan-service"}
│    │  看到完整调用链：
│    │  Gateway(2ms) → loan-service(480ms) → risk-service(450ms) → MongoDB(400ms) ← 慢查询
│    │
│    │  点击 risk-service 的 Span → "View Logs"（Tempo tracesToLogsV2）
│    │
│    ├──► Grafana Loki (关联日志)
│    │    │
│    │    │  LogQL: {deployment_environment="fat", service_name="risk-service"} | json | traceId="abc123"
│    │    │  [INFO]  收到风控评估请求 userId=张三
│    │    │  [WARN]  MongoDB 查询耗时 400ms, collection=risk_rules
│    │    │  [INFO]  风控评估完成 score=85 approved=true
│    │    │
│    │    │  定位问题：risk_rules collection 缺少索引
```

### 关联配置

```yaml
# Grafana datasources.yml.tpl（setup-grafana 通过 envsubst 渲染）

# Tempo → Loki 跳转
Tempo:
  tracesToLogsV2:
    datasourceUid: loki
    filterByTraceID: true

# Loki → Tempo 跳转
Loki:
  derivedFields:
    - matcherRegex: '"traceId":"(\w+)"'
      name: TraceID
      datasourceUid: tempo

# Tempo → Prometheus 跳转
Tempo:
  tracesToMetrics:
    datasourceUid: prometheus
  serviceMap:
    datasourceUid: prometheus
```

---

## 告警流程

```
Prometheus / Loki ruler ──评估告警规则──► 触发告警
                                          │
                                          ▼
                                Alertmanager:9093
                                  （nonprod 与 prod 各一套）
                                          │
                                ┌─────────┼─────────┐
                                ↓         ↓         ↓
                             去重       分组       静默
                                │         │         │
                                └─────────┼─────────┘
                                          │
                                ┌─────────┼─────────┐
                                ↓         ↓         ↓
                             钉钉      邮件      Slack
                           Webhook    SMTP     Webhook
```

### 告警规则示例

```yaml
# conf/prometheus/rules/infra-alerts.yml
groups:
  - name: spring-boot
    rules:
      - alert: HighP99Latency
        expr: histogram_quantile(0.99, rate(http_server_requests_seconds_bucket{env="fat"}[5m])) > 0.5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "{{ $labels.job }} P99 延迟超过 500ms (env={{ $labels.env }})"

      - alert: HighErrorRate
        expr: rate(http_server_requests_seconds_count{env="fat",status=~"5.."}[5m]) / rate(http_server_requests_seconds_count{env="fat"}[5m]) > 0.05
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.job }} 5xx 错误率超过 5% (env={{ $labels.env }})"
```

---

## 三种数据类型对比

| 维度 | Metrics（指标）| Traces（链路）| Logs（日志）|
|------|---------------|--------------|------------|
| 回答什么问题 | "系统现在怎么样？" | "这个请求经过了哪些服务？" | "当时发生了什么？" |
| 数据特征 | 数值型、可聚合 | 树状 Span 结构 | 文本型、带上下文 |
| 查询方式 | PromQL | TraceQL | LogQL |
| 存储后端 | Prometheus | Tempo | Loki |
| 采集方式 | Prometheus 主动拉取 | OTel SDK / Agent → Collector 推送 | OTel SDK / Agent → Collector 推送 |
| env 标签来源 | Prometheus `relabel_configs`（job 内固定）| `OTEL_RESOURCE_ATTRIBUTES`（Pod 级注入）| `OTEL_RESOURCE_ATTRIBUTES` |
| 多环境查询 | `{env="fat"}` | `{resource.deployment.environment="fat"}` | `{deployment_environment="fat"}` |

---

## Skill 对应关系

| 组件 | Skill | 数据类型 | 角色 |
|------|-------|---------|------|
| OTel Collector | `setup-otel-collector` | Traces, Logs | 统一接收网关 |
| Tempo | `setup-tempo` | Traces | 链路追踪后端 |
| Loki | `setup-loki` | Logs | 日志聚合后端 |
| Prometheus | `setup-prometheus` | Metrics | 指标采集 |
| Alertmanager | `setup-prometheus`（同 Compose 部署） | — | 告警去重 / 分组 / 路由 |
| Grafana | `setup-grafana` | 全部 | 统一可视化查询 |
| OTel Java Agent jar 管理 | `setup-gitlab-runner`（v1.7.0） | — | 宿主机 `/opt/tech-stack/cicd/`，volumes 挂载到 Pod |
| env 标签注入 / OTel 配置 | `setup-gitlab-runner` 的 `app.sh`（v1.5.0+）| — | Pod 部署时注入 `OTEL_RESOURCE_ATTRIBUTES` 等 |
| 双方案接入示例 | `setup-cicd/actions/integrate.md`（v1.6.0）| — | 方案 A / B / 关闭 OTel 三套完整示例 |

---

## 相关文档

- [setup-cicd/actions/integrate.md](../setup-cicd/actions/integrate.md) — Spring Boot 双方案接入完整示例（含 application.yml / pom.xml / logback-spring.xml / Apollo `ops.*` 配置）
- [setup-gitlab-runner/references/app-sh-spec.md](../setup-gitlab-runner/references/app-sh-spec.md) — app.sh 生成的 K8s 资源结构 + OTel 双方案环境变量表
- [network-architecture.md](network-architecture.md) — DNS 解析机制 + 四层域名规范 + 双入口流量
- [configuration-reference.md](configuration-reference.md) — 跨节点连接清单（含 OTel/Tempo/Loki/Prometheus/Alertmanager）
- [架构蓝图第二部分](../architecture-blueprint.md) — Apollo 多环境配置中心架构（与可观测性配置链路紧密相关）
