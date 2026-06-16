# LGT 栈 env 标签逻辑隔离实现

> **文档定位**：本文档详细描述非生产环境 LGT（Loki/Grafana/Tempo）栈的 `env` 标签逻辑隔离实现方案，包括双方案并存的 OTel 接入策略、数据流架构、组件职责和 Spring Boot 接入指南。
>
> **隶属关系**：本文档是 `architecture-blueprint.md` 第二部分的详细展开，与架构蓝图配合阅读。

---

## 目录

- [1. 整体架构](#1-整体架构)
- [2. 各组件职责](#2-各组件职责)
- [3. 日志隔离 (Loki)](#3-日志隔离-loki)
- [4. 指标隔离 (Prometheus)](#4-指标隔离-prometheus)
- [5. 链路隔离 (Tempo / OTel)](#5-链路隔离-tempo--otel)
- [6. Spring Boot 接入指南](#6-spring-boot-接入指南)
- [7. 配置示例](#7-配置示例)

---

## 设计原则

非生产环境的 LGT（Loki/Grafana/Tempo）栈部署在 K3s 外部的一套独立系统，通过 **"运行时埋点（按 SB 版本分双方案）+ OTLP 资源属性注入 + 推拉结合"** 实现按环境的数据逻辑隔离。

1. **双方案并存**：Spring Boot 3.x 主力采用 **Micrometer Observation + OTel Bridge**（云原生标准、指标零冲突）；Spring Boot 2.x 老系统无法升级时以 **Java Agent 兜底**；两套方案共用同一套 OTLP 后端与 Prometheus 拉取通道
2. **统一资源属性**：不使用 DaemonSet 和 kubernetes_sd_configs，无论哪种方案都通过 `OTEL_RESOURCE_ATTRIBUTES=deployment.environment={env}` 在 Pod 启动时注入环境标识
3. **通路解耦**：Metrics 走 Prometheus 拉取 `/actuator/prometheus`（由 Micrometer Prometheus Registry 产出），Traces / Logs 走 OTLP 推送到 OTel Collector，**指标与链路日志的数据通路完全独立，互不干扰**

---

## 1. 整体架构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│        LGT 栈 env 标签逻辑隔离 — 双方案并存（Bridge 主力 / Agent 兜底）     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  K3s Pod (Namespace: fat)                                                   │
│  ┌───────────────────────────────────────────────────────────────────┐     │
│  │  Spring Boot 应用                                                 │     │
│  │                                                                   │     │
│  │  环境变量（由 app.sh 按 ops.otelMode 条件注入）:                   │     │
│  │    OTEL_SERVICE_NAME=demo-backend                                │     │
│  │    OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-nonprod.renew.com:4317│     │
│  │    OTEL_RESOURCE_ATTRIBUTES=deployment.environment=fat           │     │
│  │    OTEL_METRICS_EXPORTER=none   # Metrics 走 Prometheus 拉取     │     │
│  │                                                                   │     │
│  │  ┌──────────────────────────────────────────────────────────┐   │     │
│  │  │  方案 A  Micrometer + OTel Bridge （SB 3.x 主力）         │   │     │
│  │  │          ops.otelMode=bridge                              │   │     │
│  │  │  ├─ Micrometer Tracing ──Bridge──→ OTel SDK               │   │     │
│  │  │  │    └─ Traces ──OTLP──→ OTel Collector → Tempo         │   │     │
│  │  │  └─ Logback + OTel Appender                               │   │     │
│  │  │        └─ Logs ────OTLP──→ OTel Collector → Loki          │   │     │
│  │  │  资源属性 deployment.environment=fat 由 SDK 自动注入       │   │     │
│  │  └──────────────────────────────────────────────────────────┘   │     │
│  │                                                                   │     │
│  │  ┌──────────────────────────────────────────────────────────┐   │     │
│  │  │  方案 B  OTel Java Agent （SB 2.x 兜底）                  │   │     │
│  │  │          ops.otelMode=agent ,  JAVA_OPTS += -javaagent    │   │     │
│  │  │  ├─ Traces ──OTLP──→ OTel Collector → Tempo              │   │     │
│  │  │  └─ Logs ────OTLP──→ OTel Collector → Loki               │   │     │
│  │  └──────────────────────────────────────────────────────────┘   │     │
│  │                                                                   │     │
│  │  ┌──────────────────────────────────────────────────────────┐   │     │
│  │  │  Spring Boot Actuator（两方案共用的指标通路）              │   │     │
│  │  │  └─ /actuator/prometheus ← Prometheus (consul_sd 拉取)    │   │     │
│  │  │      └─ 标签: env=fat (由 relabel_configs 附加)           │   │     │
│  │  └──────────────────────────────────────────────────────────┘   │     │
│  └───────────────────────────────────────────────────────────────────┘     │
│                                                                             │
│  数据流汇总:                                                                │
│    Logs:    Pod → OTel Collector → Loki           (推送，env 由 SDK 注入)  │
│    Traces:  Pod → OTel Collector → Tempo          (推送，env 由 SDK 注入)  │
│    Metrics: Pod ← Prometheus (consul_sd)           (拉取，env 由 relabel)  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. 各组件职责

| 组件 | 数据类型 | env 标签来源 | 方式 |
|------|---------|-------------|------|
| **Spring Boot** | Traces/Logs | `OTEL_RESOURCE_ATTRIBUTES=deployment.environment={env}` | 方案 A 由 OTel SDK autoconfigure 读取；方案 B 由 Agent 读取 |
| **Spring Boot** | Metrics | 应用本身不携带 env 标签（由 Prometheus 抓取端附加） | Micrometer Prometheus Registry 暴露 `/actuator/prometheus` |
| **OTel Collector** | Logs/Traces | 透传 `deployment.environment` | Resource Processor 直通 |
| **Loki** | Logs | `otlp_config.resource_attributes` 索引为标签 | 配置文件 |
| **Tempo** | Traces | Resource Attribute 原生保留 | 自动 |
| **Prometheus** | Metrics | `relabel_configs` 按 job 附加 `env` | 配置文件 |
| **Grafana** | 查询 | 按 `env` 或 `deployment.environment` 过滤 | 查询条件 |

---

## 3. 日志隔离 (Loki)

```
K3s Pod (env=fat)                                    独立服务器
┌─────────────────────────────────────┐             ┌──────────────────┐
│  Spring Boot 应用                   │             │                  │
│    方案 A: Logback + OTel Appender  │    OTLP     │   Loki 3.5+      │
│    方案 B: Agent 注入 Logback 桥接   │  ──推送──→  │   :3100/otlp     │
│      deployment.environment=fat     │             │                  │
│                                     │             │   按 env 标签存储: │
│                                     │             │   env=fat        │
└─────────────────────────────────────┘             └──────────────────┘
```

**Loki 配置**（`loki-config.yml`）：

```yaml
limits_config:
  otlp_config:
    resource_attributes:
      attributes_config:
        - action: index_label
          attributes:
            - service.name
            - deployment.environment  # 索引为可查询标签
```

**查询示例**：

```logql
# 仅查看 FAT 环境日志
{deployment_environment="fat", service_name="loan-service"} |= "ERROR"

# 对比 FAT 和 UAT 环境
{deployment_environment=~"fat|uat", service_name="risk-service"}
```

---

## 4. 指标隔离 (Prometheus)

Prometheus 使用 `consul_sd_configs` 发现服务，通过 `relabel_configs` 为每个环境附加 `env` 标签。

**前提条件**：Spring Boot 注册到 Consul 时必须打 `metrics` 标签，否则 Prometheus 无法发现：

```yaml
# Spring Boot application.yml（所有环境必须配置）
spring:
  cloud:
    consul:
      discovery:
        tags: metrics    # Prometheus consul_sd 通过此标签过滤
```

**当前实现**（`prometheus.nonprod.yml` 已配置）：

```yaml
scrape_configs:
  # Dev 环境 Spring Boot（via consul_sd）
  - job_name: 'spring-boot-dev'
    consul_sd_configs:
      - server: 'consul-dev.renew.com:8500'
        tags: ['metrics']        # 只发现带 metrics 标签的服务
    relabel_configs:
      - source_labels: [__meta_consul_service]
        target_label: job        # 服务名作为 job 标签
      - target_label: env
        replacement: dev         # 硬编码 env 标签
    metrics_path: '/actuator/prometheus'
    scrape_timeout: 10s

  # SIT / FAT / UAT 同理，各自连接对应环境的 Consul 并硬编码 env 标签
```

**其他抓取目标**（基础设施组件，通过 static_configs）：

| 组件 | 抓取地址 | 端口 | env 标签 |
|------|---------|------|---------|
| RabbitMQ | `rabbitmq-{env}.renew.com` | 15692 | 各环境独立 |
| MySQL Exporter | `mysql-{env}.renew.com` | 9104 | 各环境独立 |
| Redis Exporter | `redis-{env}.renew.com` | 9121 | 各环境独立 |
| MongoDB Exporter | `mongodb-{env}.renew.com` | 9216 | 各环境独立 |
| OTel Collector | `otel-nonprod.renew.com` | 8888 | nonprod |
| Loki | `loki-nonprod.renew.com` | 3100 | nonprod |
| Tempo | `tempo-nonprod.renew.com` | 3200 | nonprod |

**查询示例**：

```promql
# 仅查看 FAT 环境的 HTTP 请求速率
rate(http_server_requests_seconds_count{env="fat"}[5m])

# 对比各环境的 P99 延迟
histogram_quantile(0.99, rate(http_server_requests_seconds_bucket[5m])) by (env)
```

---

## 5. 链路隔离 (Tempo / OTel)

```
K3s Pod (env=fat)                                    独立服务器
┌─────────────────────────────────────┐             ┌──────────────────────────────┐
│  Spring Boot 应用                   │    OTLP     │  OTel Collector              │
│    方案 A: Micrometer Tracing       │  ──推送──→  │  otel-nonprod.renew.com:4317 │
│            ──Bridge──→ OTel SDK     │             │      │                       │
│    方案 B: Agent 字节码注入埋点      │             │      ▼                       │
│      deployment.environment=fat     │             │  Tempo 2.7+                  │
│                                     │             │  tempo-nonprod.renew.com:14317│
│                                     │             │  按 env 属性存储              │
└─────────────────────────────────────┘             └──────────────────────────────┘
```

**查询示例（TraceQL）**：

```
{resource.deployment.environment="fat" && span.http.status_code>=500}
```

---

## 6. Spring Boot 接入指南

### 6.0 版本策略总览（双方案并存）

本项目对 Spring Boot 微服务提供 **两种并存的 OTel 接入方案**，按业务应用 Spring Boot 版本自动选择：

| Spring Boot 版本 | 接入方案 | 部署形态 | 原因 |
|-----------------|---------|---------|------|
| **3.x 及以上（主力）** | **方案 A：Micrometer Observation + OTel Bridge** | pom 依赖 + application.yml + logback-spring.xml | Spring Boot 3.x 原生可观测性标准、指标零冲突、代码可治理、贴合云原生未来方向 |
| **2.x 老系统（兜底）** | **方案 B：OpenTelemetry Java Agent** | 基础镜像预置 Agent jar + `-javaagent` 启动参数 | 老系统无法升级 Micrometer Tracing 时通过字节码注入保底实现观测能力 |

**两套方案共用同一套后端**（OTel Collector / Tempo / Loki / Prometheus），数据格式统一，可在 Grafana 中跨服务关联查询。

**选择流程**：

```
业务应用 Spring Boot 版本 ≥ 3.0  &&  JDK ≥ 17?
    │
    ├── 是 → 方案 A (Micrometer + Bridge) — 默认主推 ★
    │
    └── 否 → 方案 B (Java Agent)          — 仅限老系统兜底
```

**关键差异**：

| 维度 | 方案 A (Bridge) | 方案 B (Agent) |
|------|----------------|----------------|
| 指标来源 | **仅 Micrometer Prometheus Registry 单一来源** | 需显式关闭 Agent 指标导出，否则会与 Actuator 指标重复 |
| 链路埋点 | Micrometer Observation + Bridge 桥接到 OTel SDK | Agent 字节码注入（覆盖 JDBC/Redis/HTTP 等常用库） |
| 日志出口 | OTel Logback Appender（pom 显式依赖） | Agent 自动注入 Logback 桥接 |
| 代码可见性 | 依赖在 pom，埋点可通过 `Observation` API 自定义 | 完全无感；自定义埋点需额外 API |
| 启动开销 | 无 Agent 附加成本 | +300~800 ms 启动、+30~80 MB 堆外内存 |
| GraalVM Native | 支持 | 不支持 |

### 6.1 Apollo 配置项

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `ops.supportOtel` | `true` | 是否启用 OTel 链路追踪和日志采集 |
| `ops.otelMode` | `bridge` | `bridge`（SB 3.x 主力）/ `agent`（SB 2.x 兜底） |
| `ops.appDomain` | 空 | 域名（创建 Ingress） |
| `ops.javaVersion` | `21` | JDK 版本；`< 17` 时 app.sh 自动强制 `ops.otelMode=agent` |

> **app.sh 约束**：当 `ops.javaVersion` 低于 17，app.sh 自动把 `ops.otelMode` 覆写为 `agent`，因为 Micrometer Tracing 1.4.x 需要 JDK 17+。

---

### 6.2 方案 A：Micrometer Observation + OTel Bridge（Spring Boot 3.x 主力方案）

**核心原则**：指标、链路、日志统一走 Spring Boot 原生 Observability 能力，OTel 只作为"导出协议"存在，不做埋点。

#### 6.2.1 pom.xml 依赖

```xml
<dependencies>
    <!-- ============ 指标 (Metrics) ============ -->
    <!-- Actuator 暴露 /actuator/prometheus 端点 -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-actuator</artifactId>
    </dependency>
    <!-- Micrometer Prometheus Registry：Prometheus 拉取的指标来源 -->
    <dependency>
        <groupId>io.micrometer</groupId>
        <artifactId>micrometer-registry-prometheus</artifactId>
    </dependency>

    <!-- ============ 链路 (Traces) ============ -->
    <!-- Micrometer Tracing → OTel 桥接：SB 3.x 原生方式 -->
    <dependency>
        <groupId>io.micrometer</groupId>
        <artifactId>micrometer-tracing-bridge-otel</artifactId>
    </dependency>
    <!-- OTLP Exporter：通过 gRPC 发送到 OTel Collector -->
    <dependency>
        <groupId>io.opentelemetry</groupId>
        <artifactId>opentelemetry-exporter-otlp</artifactId>
    </dependency>

    <!-- ============ 日志 (Logs) ============ -->
    <!-- OTel Logback Appender：Logback 日志经 OTLP 推出 -->
    <dependency>
        <groupId>io.opentelemetry.instrumentation</groupId>
        <artifactId>opentelemetry-logback-appender-1.0</artifactId>
    </dependency>

    <!-- ============ 服务发现 (for Prometheus) ============ -->
    <dependency>
        <groupId>org.springframework.cloud</groupId>
        <artifactId>spring-cloud-starter-consul-discovery</artifactId>
    </dependency>

    <!-- ============ 配置中心 ============ -->
    <dependency>
        <groupId>com.ctrip.framework.apollo</groupId>
        <artifactId>apollo-client</artifactId>
        <version>2.4.0</version>
    </dependency>
</dependencies>
```

#### 6.2.2 application.yml

```yaml
spring:
  application:
    name: ${APP_ID:demo-backend}

  # ============ Consul 服务注册（用于 Prometheus 服务发现）============
  cloud:
    consul:
      host: consul-${spring.profiles.active}.renew.com
      port: 8500
      discovery:
        tags: metrics              # 必须：Prometheus consul_sd 通过此标签过滤
        health-check-interval: 10s

# ============ Actuator / 指标导出 ============
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  endpoint:
    health:
      show-details: always
  prometheus:
    metrics:
      export:
        enabled: true
  # ============ 链路采样 ============
  tracing:
    sampling:
      probability: 1.0        # 非生产 100%，生产按需下调（如 0.1）
  # ============ OTLP 导出端点（Traces） ============
  otlp:
    tracing:
      endpoint: ${OTEL_EXPORTER_OTLP_ENDPOINT}
      # 由 app.sh 按环境注入：http://otel-{nonprod|prod}.renew.com:4317
```

> `/actuator/prometheus` 端点由 Micrometer 产生；链路通过 Micrometer Tracing Bridge 转换为 OTel Span 后推送。**Prometheus 与 OTLP 两条通路完全独立，不会产生重复指标**。

#### 6.2.3 logback-spring.xml

```xml
<configuration>
    <include resource="org/springframework/boot/logging/logback/defaults.xml"/>

    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder>
            <pattern>%d{yyyy-MM-dd HH:mm:ss} [%thread] [traceId=%X{traceId:-},spanId=%X{spanId:-}] %-5level %logger{36} - %msg%n</pattern>
        </encoder>
    </appender>

    <!-- OTel OTLP Appender：把日志经由 SDK 推到 OTel Collector -->
    <appender name="OTEL" class="io.opentelemetry.instrumentation.logback.appender.v1_0.OpenTelemetryAppender">
        <captureExperimentalAttributes>true</captureExperimentalAttributes>
        <captureCodeAttributes>true</captureCodeAttributes>
        <captureMdcAttributes>*</captureMdcAttributes>
    </appender>

    <root level="INFO">
        <appender-ref ref="CONSOLE"/>
        <appender-ref ref="OTEL"/>
    </root>
</configuration>
```

> 启动时必须调用 `OpenTelemetryAppender.install(openTelemetry)` 把 Appender 与 SDK 实例绑定。可通过以下 Bean 完成：
>
> ```java
> @Configuration
> public class OtelLogbackConfig {
>     OtelLogbackConfig(OpenTelemetry openTelemetry) {
>         OpenTelemetryAppender.install(openTelemetry);
>     }
> }
> ```

#### 6.2.4 app.sh 生成的环境变量（方案 A）

```yaml
env:
# ============ JVM 配置（无 -javaagent） ============
- name: JAVA_OPTS
  value: >-
    {ops.javaCmdOptions}
    -Xmx{内存}m -Xms{内存}m
    -Dapp.id={appId}
    -Dapollo.meta=http://apollo-config-{env}.renew.com

# ============ Spring 环境标识 ============
- name: SPRING_PROFILES_ACTIVE
  value: "{env}"

# ============ OTel SDK 配置（由 autoconfigure 读取） ============
- name: OTEL_SERVICE_NAME
  value: "{appId}"

- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: "http://otel-{domainEnv}.renew.com:4317"

- name: OTEL_EXPORTER_OTLP_PROTOCOL
  value: "grpc"

- name: OTEL_RESOURCE_ATTRIBUTES
  value: "deployment.environment={env},service.namespace={env}"
  # 核心：env 标签注入，用于 Logs/Traces 环境隔离

- name: OTEL_METRICS_EXPORTER
  value: "none"
  # Metrics 由 Prometheus 拉取 /actuator/prometheus，不走 OTLP

- name: OTEL_LOGS_EXPORTER
  value: "otlp"

- name: OTEL_TRACES_EXPORTER
  value: "otlp"
```

#### 6.2.5 为什么主力选方案 A

1. **指标单一来源**：Prometheus 只拉 `/actuator/prometheus`，OTel SDK 不产生任何指标（`OTEL_METRICS_EXPORTER=none`），**彻底避免 `http_server_requests_seconds_*` 与 `http.server.duration` 两套指标并存打架**
2. **云原生标准化**：Micrometer Observation API 是 Spring Boot 3.x 原生的可观测性门面，后续切换后端（Zipkin/Jaeger）只需换 Bridge，业务代码零改动
3. **依赖可见**：pom 里的观测依赖清晰可审计，版本由公司级 BOM 统一管控
4. **可自定义埋点**：业务代码可直接用 `ObservationRegistry` / `@Observed` 做领域级埋点，观测能力随业务下沉
5. **Native Image 友好**：未来 GraalVM Native 无障碍

---

### 6.3 方案 B：Java Agent（Spring Boot 2.x 兜底方案）

**使用场景**：仅在业务为 Spring Boot 2.x 且无法升级、或 JDK 版本 `< 17` 时使用。新建项目一律用方案 A。

#### 6.3.1 OTel Agent 部署方式

OTel Agent 由 `setup-gitlab-runner` 统一管理，作为 CI/CD 基础设施的一部分，而非集成到业务基础镜像：

**部署方式**：

```
宿主机：/opt/tech-stack/cicd/opentelemetry-javaagent.jar (v2.26.1)
    ↓ config.toml volumes 挂载
容器内：/opt/otel/opentelemetry-javaagent.jar
```

**优势**：

- **跨版本通用**：一个 Agent 文件兼容 JDK 8~21，无需维护多个基础镜像
- **更新简单**：替换一个文件即可，无需重建和推送镜像
- **管理集中**：与 app.sh/settings.xml/kubectl-bin 管理方式一致

**setup-gitlab-runner start 步骤 5.4** 自动下载 Agent 到 `/opt/tech-stack/cicd/`：

```bash
curl -sfL https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.26.1/opentelemetry-javaagent.jar \
  -o /opt/tech-stack/cicd/opentelemetry-javaagent.jar
```

**业务 Dockerfile**：使用标准 JDK 基础镜像即可，无需特殊处理：

```dockerfile
FROM harbor.renew.com/library/jdk:11
# Agent 由 K8s volumes 挂载，镜像内无需预置
```

**app.sh 注入 javaagent**（当 `ops.otelMode=agent` 时）：

```bash
javaCmdOptions="${javaCmdOptions} -javaagent:/opt/otel/opentelemetry-javaagent.jar"
```

#### 6.3.2 pom.xml 依赖（SB 2.x 版）

```xml
<dependencies>
    <!-- Actuator + Micrometer Prometheus：指标通路必备 -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-actuator</artifactId>
    </dependency>
    <dependency>
        <groupId>io.micrometer</groupId>
        <artifactId>micrometer-registry-prometheus</artifactId>
    </dependency>

    <!-- Consul 服务注册 -->
    <dependency>
        <groupId>org.springframework.cloud</groupId>
        <artifactId>spring-cloud-starter-consul-discovery</artifactId>
    </dependency>

    <!-- Apollo 客户端 -->
    <dependency>
        <groupId>com.ctrip.framework.apollo</groupId>
        <artifactId>apollo-client</artifactId>
        <version>2.4.0</version>
    </dependency>

    <!-- 注意：方案 B 的链路/日志通路由 Agent 负责，无需在 pom 引入 micrometer-tracing-bridge-otel 或 logback-appender -->
</dependencies>
```

#### 6.3.3 application.yml（SB 2.x 版）

```yaml
spring:
  application:
    name: ${APP_ID:legacy-service}

  # ============ Consul 服务注册 ============
  cloud:
    consul:
      host: consul-${spring.profiles.active}.renew.com
      port: 8500
      discovery:
        tags: metrics              # 必须：Prometheus 通过此标签发现服务
        health-check-interval: 10s

  # ============ Apollo 配置 ============
  apollo:
    bootstrap:
      enabled: true
    meta: http://apollo-config-${spring.profiles.active}.renew.com

# ============ Actuator / 指标导出 ============
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
  endpoint:
    health:
      show-details: always
  metrics:
    export:
      prometheus:
        enabled: true
```

> **说明**：SB 2.x 不支持 `management.tracing.sampling` 等原生可观测性配置，链路采样通过 Agent 环境变量 `OTEL_TRACES_SAMPLER` 控制。

#### 6.3.4 app.sh 生成的环境变量（方案 B）

```yaml
env:
# ============ JVM 配置（附加 -javaagent） ============
- name: JAVA_OPTS
  value: >-
    {ops.javaCmdOptions}
    -Xmx{内存}m -Xms{内存}m
    -Dapp.id={appId}
    -Dapollo.meta=http://apollo-config-{env}.renew.com
    -javaagent:/opt/otel/opentelemetry-javaagent.jar

- name: SPRING_PROFILES_ACTIVE
  value: "{env}"

- name: OTEL_SERVICE_NAME
  value: "{appId}"

- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: "http://otel-{domainEnv}.renew.com:4317"

- name: OTEL_RESOURCE_ATTRIBUTES
  value: "deployment.environment={env},service.namespace={env}"

# ⚠️ 关键：关闭 Agent 指标导出，避免与 Actuator/Micrometer 重复
- name: OTEL_METRICS_EXPORTER
  value: "none"

- name: OTEL_LOGS_EXPORTER
  value: "otlp"

- name: OTEL_TRACES_EXPORTER
  value: "otlp"

# ⚠️ 关闭 Agent 的 Micrometer Bridge（避免 Agent 读取 Actuator 并再次导出）
- name: OTEL_INSTRUMENTATION_MICROMETER_ENABLED
  value: "false"
```

#### 6.3.5 注意事项

- **指标去重是必做项**：Agent 默认会产生 `http.server.duration` 类指标，与 Actuator 的 `http_server_requests_seconds_*` 语义重叠，必须通过 `OTEL_METRICS_EXPORTER=none` 关闭
- **Agent 版本锁定**：当前锁定 `opentelemetry-javaagent 2.11.x` ↔ OTel Collector `0.120.0`，跨大版本升级须同步测试
- **启动自检**：Agent 加载成功时 stdout 会输出 `[otel.javaagent] INFO - OpenTelemetry Javaagent: X.X.X`，可作为 readiness probe 辅助判定

---

### 6.4 关闭 OTel（`ops.supportOtel=false`）

适用场景：临时排查、特殊合规要求、或历史项目尚未接入观测能力时。

此时 app.sh **不注入任何 `OTEL_*` 环境变量、也不加 `-javaagent`**：

- ✅ **Metrics 仍正常**：Prometheus 通过 Consul 发现服务，照常拉取 `/actuator/prometheus`
- ❌ Traces / Logs 不推送到 OTel Collector
- ❌ Grafana 中该服务无法通过 traceId 关联跳转

**降级路径示意**：

```
supportOtel=false 时的数据流
  Spring Boot ──/actuator/prometheus──→ Prometheus    ✅ Metrics 正常
  Spring Boot ────×──── OTel Collector                 ❌ Traces/Logs 缺失
```

---

### 6.5 env 与 domainEnv 映射

```bash
# app.sh 中的逻辑
# ENV = dev|sit|fat|uat|prod (部署目标环境)
# DOMAIN_ENV = nonprod|prod (OTel Collector 域级域名)

if [[ "${ENV}" == "prod" ]]; then
  DOMAIN_ENV="prod"
else
  DOMAIN_ENV="nonprod"
fi
```

| 部署环境 (ENV) | OTel Collector 域名 (DOMAIN_ENV) | OTLP Endpoint |
|---------------|----------------------------------|---------------|
| dev | nonprod | `otel-nonprod.renew.com:4317` |
| sit | nonprod | `otel-nonprod.renew.com:4317` |
| fat | nonprod | `otel-nonprod.renew.com:4317` |
| uat | nonprod | `otel-nonprod.renew.com:4317` |
| prod | prod | `otel-prod.renew.com:4317` |

---

## 7. 配置示例

### Spring Boot 3.x 新项目（方案 A：Micrometer + Bridge）

```properties
# Apollo 项目 namespace 配置
ops.k8sReplicas = 2
ops.appCpuLimit = 1
ops.appMemoryLimit = 2048
ops.appDomain = order.fat.api.renew.com
ops.javaVersion = 21
ops.supportOtel = true      # 启用链路追踪和日志采集
ops.otelMode = bridge       # SB 3.x 主力方案（默认值，可省略）
```

### Spring Boot 2.x 老项目（方案 B：Java Agent 兜底）

```properties
# Apollo 项目 namespace 配置
ops.k8sReplicas = 1
ops.appCpuLimit = 0.5
ops.appMemoryLimit = 512
ops.appDomain = legacy.fat.api.renew.com
ops.javaVersion = 11
ops.supportOtel = true      # 启用链路追踪和日志采集
ops.otelMode = agent        # JDK <17 自动强制切换，也可显式指定
```

### 禁用 OTel（仅保留 Prometheus 指标）

```properties
# Apollo 项目 namespace 配置
ops.k8sReplicas = 1
ops.appCpuLimit = 0.5
ops.appMemoryLimit = 512
ops.appDomain = internal.fat.api.renew.com
ops.javaVersion = 21
ops.supportOtel = false     # 禁用链路和日志推送
# ops.otelMode 在 supportOtel=false 时忽略
```

> **注意**：禁用 OTel 后，应用日志和链路不会推送到 Loki/Tempo，但 Prometheus 指标仍可通过 `/actuator/prometheus` 正常采集。
