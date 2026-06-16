# action: integrate — 正式项目接入 CI/CD

> **目标**：一个已有的 Spring Boot / 前端 / Python 项目，完成以下 3 步后推送代码即可在 GitLab Pipeline 看到结果。

## 前提条件

- `setup-gitlab-runner start` 已执行（app.sh、kubeconfig、Harbor 基础镜像、Harbor Secret 已就绪）
- GitLab Runner 已通过 `setup-gitlab-runner register` 注册并在线
- Apollo Portal 可访问：`http://apollo.renew.com`
- Apollo `tech.common` 公共 namespace 已导入配置模板（模板位于 `<skill_dir>/references/apollo-tech-common.properties`）

---

## 步骤 1：Apollo — 创建应用并配置

### 1.1 创建 AppId

访问 `http://apollo.renew.com`：

1. **应用管理 → 创建应用**
2. AppId 填写项目名（必须与 `.gitlab-ci.yml` 中 `APP_ID` 一致）
   - 格式：小写字母、数字、短横线（如 `order-service`、`user-web`）
3. **关联公共 Namespace**：进入应用 → Namespace 管理 → 添加公共 namespace → `tech.common`

### 1.2 配置必须覆盖的项（在项目自己的 namespace 或 tech.common 中配置）

**Java 项目最小覆盖配置**（可复制粘贴）：

```properties
# Java 项目配置
# 必须配置
ops.appDomain=order.fat.api.renew.com    # 外部访问域名，不配置则无 Ingress

# 建议配置
ops.appMemoryLimit=2048                   # Java 默认 1024，生产建议 2048+
ops.k8sReplicas=1                         # 默认 1，生产建议 2
```

**前端项目最小覆盖配置**（可复制粘贴）：

```properties
# 前端项目配置
# 必须配置
ops.appDomain=order.fat.web.renew.com    # 外部访问域名

# 建议配置
ops.appMemoryLimit=128                    # 前端 Nginx，128Mi 足够
ops.appCpuLimit=0.2                       # 前端 CPU 消耗低
```

**Python 项目必须额外配置**（可复制粘贴）：

```properties
# Python 项目配置
# 必须配置
ops.appPort=8000                          # Python 不自动检测端口，必须配置
ops.appDomain=ai.fat.api.renew.com        # 外部访问域名

# 建议配置
ops.appHealthUri=/health                  # 健康检查路径
ops.autoReuseImage=false                  # Python 默认 true 可能复用旧镜像
ops.appMemoryLimit=512                    # 最低 256，低于此值 Pod 无法创建
```

### 1.3 发布配置

在 Apollo Portal 点击**发布**，配置立即生效。

---

## 步骤 2：项目代码 — 添加必要文件

> **GitLab Variables**：无需配置。
> - `HARBOR_PASSWORD`：由 `setup-gitlab-runner start` 在部署时注入到 `/opt/tech-stack/cicd/app.sh`
> - `KUBECONFIG`：由 `setup-gitlab-runner` 分发到 `/opt/tech-stack/cicd/kubeconfig`，CI Job 自动挂载
> 
> 钉钉通知在项目 `.gitlab-ci.yml` 的 `variables` 中按需开启（已提供注释模板）。

### 2.1 添加 `.gitlab-ci.yml`

复制对应模板并修改 `APP_ID`：

**Java 后端项目**：

```bash
# 从 skill 目录复制模板
cp <skill_dir>/references/.gitlab-ci.yml .gitlab-ci.yml
```

只需修改一处：

```yaml
# 找到 variables 块，修改 APP_ID 为你的项目 AppId
variables:
  APP_ID: 'order-service'   # ← 改这里，与 Apollo AppId 一致
  APP_SUB_DIR: ''           # 聚合项目时填子目录名，其余留空
```

**前端项目**：

```bash
cp <skill_dir>/references/demo-frontend/.gitlab-ci.yml .gitlab-ci.yml
# 修改 APP_ID 为前端项目 AppId
```

**聚合项目（一个 Git 仓库多个微服务）**：

```bash
cp <skill_dir>/references/.gitlab-ci-aggregated.yml .gitlab-ci.yml
# 按注释修改每个微服务的 APP_ID 和 APP_SUB_DIR
```

---

### 2.2 Spring Boot 基础设施接入

> 本技术栈适配 **Spring Boot 3.5.x + JDK 21 + Spring Cloud 2025.0**。

#### 2.2.1 版本对应关系

| 业务框架 | 版本 | 对应基础设施 |
|---------|------|-------------|
| JDK | 21 | 所有 Java 服务 |
| Spring Boot | 3.5.x | MySQL 8.4, Redis 8.0, MongoDB 8.0 |
| Spring Cloud | 2025.0.0 (Northfields) | Consul 1.20 |
| Apollo Client | 2.4.0 | Apollo 2.5.0 |
| Redisson | 4.3.0 | Redis 8.0 |

#### 2.2.2 通用依赖（pom.xml）

以下依赖为所有 Spring Boot 项目必须配置：

**数据存储**：

```xml
<!-- MySQL -->
<dependency>
    <groupId>com.mysql</groupId>
    <artifactId>mysql-connector-j</artifactId>
</dependency>

<!-- Redis (Redisson) -->
<dependency>
    <groupId>org.redisson</groupId>
    <artifactId>redisson-spring-boot-starter</artifactId>
    <version>4.3.0</version>
</dependency>

<!-- MongoDB -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-mongodb</artifactId>
</dependency>
```

**消息中间件**：

```xml
<!-- RabbitMQ -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-amqp</artifactId>
</dependency>
```

**服务治理**：

```xml
<!-- Consul 服务发现 -->
<dependency>
    <groupId>org.springframework.cloud</groupId>
    <artifactId>spring-cloud-starter-consul-discovery</artifactId>
</dependency>

<!-- Apollo 配置中心 -->
<dependency>
    <groupId>com.ctrip.framework.apollo</groupId>
    <artifactId>apollo-client</artifactId>
    <version>2.4.0</version>
</dependency>
```

#### 2.2.3 可观测性依赖

可观测性依赖与 OTel 方案相关，**详见 2.5 节**：

- **方案 A (Micrometer + Bridge)**：Actuator + Prometheus + OTel Bridge + Logback Appender
- **方案 B (Java Agent)**：仅需 Actuator + Prometheus

---

### 2.3 application.yml 通用配置

以下配置为所有 Spring Boot 项目通用的中间件连接配置：

```yaml
spring:
  application:
    name: order-service   # 与 AppId 一致

  # MySQL（本地开发用 fat 环境，CI/CD 部署时从 Apollo 读取实际环境地址）
  datasource:
    url: jdbc:mysql://${MYSQL_HOST:mysql-fat.renew.com}:3306/your_db?useSSL=false&serverTimezone=Asia/Shanghai
    username: ${MYSQL_USER:app_user}
    password: ${MYSQL_PASSWORD:your_password}
    driver-class-name: com.mysql.cj.jdbc.Driver
    hikari:
      maximum-pool-size: 20
      minimum-idle: 5
      connection-timeout: 30000

  # Redis + MongoDB
  data:
    redis:
      host: ${REDIS_HOST:redis-fat.renew.com}
      port: 6379
      password: ${REDIS_PASSWORD:your_redis_password}
    mongodb:
      uri: mongodb://${MONGO_USER:app_user}:${MONGO_PASSWORD:your_password}@${MONGO_HOST:mongodb-fat.renew.com}:27017/your_db?authSource=your_db

  # RabbitMQ
  rabbitmq:
    host: ${RABBITMQ_HOST:rabbitmq-fat.renew.com}
    port: 5672
    username: ${RABBITMQ_USER:admin}
    password: ${RABBITMQ_PASSWORD:your_mq_password}
    virtual-host: /

  # Consul 服务发现
  cloud:
    consul:
      host: consul-${spring.profiles.active}.renew.com
      port: 8500
      discovery:
        service-name: ${spring.application.name}
        health-check-interval: 10s
        tags:
          - metrics    # 让 Prometheus 通过 consul_sd 自动发现

# Apollo 配置中心
# apollo.meta 放在 src/main/resources/META-INF/app.properties（本地开发）
# CI/CD 部署时 app.sh 通过 -Dapollo.meta=http://apollo-config-{env}.renew.com 注入
apollo:
  bootstrap:
    enabled: true
    eagerLoad:
      enabled: true    # 确保 Consul host/port 在 Spring Cloud 自动配置前加载完毕
    namespaces: application
```

> **中间件地址说明**：
> - 本地开发默认连接 FAT 环境中间件
> - CI/CD 部署时，各环境中间件地址在 Apollo application namespace 中配置

> **OTel 可观测性配置**：根据所选方案（A/B），在 2.5 节中添加对应的 application.yml 配置。

---

### 2.4 Apollo 配置（运行时）

在 **Apollo Portal → 应用 → application namespace** 中配置：

```properties
# Consul 连接（运行时从 Apollo 读取，而非硬编码在 application.yml）
spring.cloud.consul.host = consul-${spring.profiles.active}.renew.com
spring.cloud.consul.port = 8500
spring.cloud.consul.discovery.prefer-ip-address = true

# 中间件地址（与 consul 同样使用 ${spring.profiles.active} 占位符按环境自动切换）
MYSQL_HOST = mysql-${spring.profiles.active}.renew.com
REDIS_HOST = redis-${spring.profiles.active}.renew.com
MONGO_HOST = mongodb-${spring.profiles.active}.renew.com
RABBITMQ_HOST = rabbitmq-${spring.profiles.active}.renew.com
```

> **说明**：`apollo.meta` 放在 `app.properties` 而非 `application.yml`，CI/CD 部署时 app.sh 通过 `-Dapollo.meta` JVM 参数注入正确环境地址（优先级更高），`app.properties` 仅作本地开发回退。

---

### 2.5 OTel 双方案选择

> 根据 Spring Boot 版本和 JDK 版本，选择合适的 OTel 接入方案。

#### 2.5.1 版本策略总览

| 方案 | 适用场景 | JDK 要求 | Spring Boot | 部署形态 |
|------|---------|---------|-------------|---------|
| **方案 A: Bridge** | Spring Boot 3.x 主力项目 | JDK 17+ | 3.0+ | pom 依赖 + application.yml + logback-spring.xml |
| **方案 B: Agent** | Spring Boot 2.x 老系统兜底 | JDK 8+ | 2.x | 宿主机 `/opt/tech-stack/cicd/opentelemetry-javaagent.jar`（由 setup-gitlab-runner 统一管理）→ volumes 挂载到容器 `/opt/otel/` → app.sh 自动注入 `-javaagent` |

**选择流程**：

```
业务应用 Spring Boot 版本 ≥ 3.0  &&  JDK ≥ 17?
    │
    ├── 是 → 方案 A (Micrometer + Bridge) — 默认主推
    │
    └── 否 → 方案 B (Java Agent)          — 仅限老系统兜底
```

**关键差异**：

| 维度 | 方案 A (Bridge) | 方案 B (Agent) |
|------|----------------|----------------|
| 指标来源 | **仅 Micrometer Prometheus Registry 单一来源** | 需显式关闭 Agent 指标导出，否则会与 Actuator 指标重复 |
| 链路埋点 | Micrometer Observation + Bridge 桥接到 OTel SDK | Agent 字节码注入 |
| 日志出口 | OTel Logback Appender（pom 显式依赖） | Agent 自动注入 Logback 桥接 |
| 代码可见性 | 依赖在 pom，埋点可通过 `Observation` API 自定义 | 完全无感；自定义埋点需额外 API |
| 启动开销 | 无 Agent 附加成本 | +300~800 ms 启动、+30~80 MB 堆外内存 |
| GraalVM Native | 支持 | 不支持 |

---

#### 2.5.2 方案 A：Micrometer + OTel Bridge（推荐）

> Spring Boot 3.x 主力方案，使用原生 Observability 能力。

**核心原则**：指标、链路、日志统一走 Spring Boot 原生 Observability 能力，OTel 只作为"导出协议"存在。

**Apollo 配置**：

```properties
ops.supportOtel = true      # 启用链路追踪和日志采集
ops.otelMode = bridge       # 方案 A（默认值）
```

**pom.xml 依赖**：

```xml
<!-- ============ 指标 (Metrics) ============ -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>

<!-- ============ 链路 (Traces) ============ -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-tracing-bridge-otel</artifactId>
</dependency>
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-otlp</artifactId>
</dependency>

<!-- ============ 日志 (Logs) ============ -->
<dependency>
    <groupId>io.opentelemetry.instrumentation</groupId>
    <artifactId>opentelemetry-logback-appender-1.0</artifactId>
</dependency>
```

**application.yml（OTel 部分）**：

在 2.3 节通用配置基础上追加：

```yaml
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
      endpoint: ${OTEL_EXPORTER_OTLP_ENDPOINT:http://otel-nonprod.renew.com:4317}
      # 由 app.sh 按环境注入：http://otel-{nonprod|prod}.renew.com:4317
```

> `/actuator/prometheus` 端点由 Micrometer 产生；链路通过 Micrometer Tracing Bridge 转换为 OTel Span 后推送。**Prometheus 与 OTLP 两条通路完全独立，不会产生重复指标**。

**logback-spring.xml**：

创建 `src/main/resources/logback-spring.xml`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
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

> **重要**：启动时必须调用 `OpenTelemetryAppender.install(openTelemetry)` 把 Appender 与 SDK 实例绑定：

```java
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.instrumentation.logback.appender.v1_0.OpenTelemetryAppender;
import org.springframework.context.annotation.Configuration;

@Configuration
public class OtelLogbackConfig {
    OtelLogbackConfig(OpenTelemetry openTelemetry) {
        OpenTelemetryAppender.install(openTelemetry);
    }
}
```

**app.sh 生成的环境变量（方案 A）**：

```yaml
env:
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

**为什么主力选方案 A**：

1. **指标单一来源**：Prometheus 只拉 `/actuator/prometheus`，OTel SDK 不产生任何指标，**彻底避免指标重复**
2. **云原生标准化**：Micrometer Observation API 是 Spring Boot 3.x 原生的可观测性门面
3. **依赖可见**：pom 里的观测依赖清晰可审计，版本由公司级 BOM 统一管控
4. **可自定义埋点**：业务代码可直接用 `ObservationRegistry` / `@Observed` 做领域级埋点
5. **Native Image 友好**：未来 GraalVM Native 无障碍

---

#### 2.5.3 方案 B：OTel Java Agent（兜底）

> Spring Boot 2.x 老系统使用，无需修改代码。新建项目一律用方案 A。

**使用场景**：仅在业务为 Spring Boot 2.x 且无法升级、或 JDK 版本 `< 17` 时使用。

**Apollo 配置**：

```properties
ops.supportOtel = true      # 启用链路追踪和日志采集
ops.otelMode = agent        # 方案 B
# 注意：JDK < 17 时，app.sh 会自动强制切换为 agent 模式
```

**OTel Agent 部署方式**：

OTel Agent 由 `setup-gitlab-runner` 统一管理，作为 CI/CD 基础设施的一部分：

```
宿主机：/opt/tech-stack/cicd/opentelemetry-javaagent.jar (v2.26.1)
    ↓ config.toml volumes 挂载
容器内：/opt/otel/opentelemetry-javaagent.jar
```

**业务 Dockerfile**：使用标准 JDK 基础镜像即可，无需特殊处理：

```dockerfile
FROM harbor.renew.com/library/jdk:11
# Agent 由 K8s volumes 挂载，镜像内无需预置
```

**pom.xml 依赖**：

```xml
<!-- Actuator + Micrometer Prometheus：指标通路必备 -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>

<!-- 注意：方案 B 的链路/日志通路由 Agent 负责，无需 micrometer-tracing-bridge-otel 或 logback-appender -->
```

**application.yml（SB 2.x 版）**：

在 2.3 节通用配置基础上调整（无需 OTLP 配置）：

```yaml
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

# 注意：不需要 management.otlp.tracing 和 management.tracing.sampling
# 链路/日志由 Agent 自动处理，采样率通过 OTEL_TRACES_SAMPLER 环境变量控制
```

**logback-spring.xml**：**不需要配置 OTel Appender**，Agent 会自动注入 traceId 到 MDC。

**app.sh 生成的环境变量（方案 B）**：

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

# ⚠️ 关闭 Agent 的 Micrometer Bridge
- name: OTEL_INSTRUMENTATION_MICROMETER_ENABLED
  value: "false"
```

> **重要**：方案 B 必须设置 `OTEL_METRICS_EXPORTER=none` 和 `OTEL_INSTRUMENTATION_MICROMETER_ENABLED=false`，否则 Agent 会额外导出 `http.server.duration` 指标，与 Actuator 的 `http_server_requests_seconds_*` 重复。

---

#### 2.5.4 方案 A vs B 配置对比

| 配置项 | 方案 A (Bridge) | 方案 B (Agent) |
|--------|----------------|----------------|
| `management.otlp.tracing.endpoint` | ✅ 需要配置 | ❌ 不需要（Agent 处理） |
| `management.tracing.sampling.probability` | ✅ 需要配置 | ❌ 不需要（Agent 环境变量控制） |
| `logback-spring.xml` OTel Appender | ✅ 需要配置 | ❌ 不需要（Agent 自动注入） |
| Java 代码（OpenTelemetryAppender.install） | ✅ 需要配置 | ❌ 不需要 |
| `-javaagent` 启动参数 | ❌ 不需要 | ✅ 自动注入 |
| JDK 要求 | JDK 17+ | JDK 8+ |
| Spring Boot 要求 | 3.x | 2.x / 3.x |

---

#### 2.5.5 关闭 OTel（ops.supportOtel=false）

适用场景：临时排查、特殊合规要求、或历史项目尚未接入观测能力时。

**Apollo 配置**：

```properties
ops.supportOtel = false     # 禁用链路和日志推送
```

此时 app.sh **不注入任何 `OTEL_*` 环境变量、也不加 `-javaagent`**：

- ✅ **Metrics 仍正常**：Prometheus 通过 Consul 发现服务，照常拉取 `/actuator/prometheus`
- ❌ Traces / Logs 不推送到 OTel Collector
- ❌ Grafana 中该服务无法通过 traceId 关联跳转

**最小化 application.yml**（仅保留 Actuator + Consul + Apollo，无任何 OTel 相关配置）：

```yaml
spring:
  application:
    name: ${APP_ID:legacy-service}

  # ============ Consul 服务注册（Prometheus consul_sd 仍可发现） ============
  cloud:
    consul:
      host: consul-${spring.profiles.active}.renew.com
      port: 8500
      discovery:
        tags: metrics              # Prometheus 抓取仍依赖此 tag
        health-check-interval: 10s

  # ============ Apollo 配置 ============
  apollo:
    bootstrap:
      enabled: true

# ============ Actuator / Prometheus 指标导出（保留） ============
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
  endpoint:
    health:
      show-details: always
  prometheus:
    metrics:
      export:
        enabled: true

# 注意：相比方案 A，删除了 management.tracing.* / management.otlp.* 配置；
#       logback-spring.xml 也无需 OpenTelemetryAppender；pom 也无需 micrometer-tracing-bridge-otel
#       与 opentelemetry-logback-appender 依赖。
```

**对应 pom.xml 最小依赖**（仅指标 + Consul + Apollo）：

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.cloud</groupId>
    <artifactId>spring-cloud-starter-consul-discovery</artifactId>
</dependency>
<dependency>
    <groupId>com.ctrip.framework.apollo</groupId>
    <artifactId>apollo-client</artifactId>
    <version>2.4.0</version>
</dependency>
```

---

### 2.6 本地开发配置（app.properties）

在 `src/main/resources/META-INF/app.properties` 中配置：

```properties
# app.id：CI/CD 部署时由 app.sh 注入 -Dapp.id=xxx（优先级更高），本地开发从此读取
app.id=order-service

# apollo.meta：CI/CD 部署时由 app.sh 根据环境自动注入 -Dapollo.meta=http://apollo-config-{env}.renew.com
apollo.meta=http://apollo-config-fat.renew.com

apollo.cacheDir=./config
```

---

## 步骤 3：推送代码触发 Pipeline

```bash
git checkout -b dev
git add .gitlab-ci.yml src/main/resources/META-INF/app.properties
git commit -m "feat: 接入 CI/CD 流水线"
git push -u origin dev
```

**在 GitLab 手动触发部署**：

1. 访问项目 → CI/CD → Pipelines
2. 等待 `jar`（或 `build`）stage 完成
3. 点击 `fat_deploy` → 右侧三角按钮手动触发

**Pipeline 流程**：

```
jar/build stage（自动）
    ↓ Maven 编译 / npm build
fat_deploy（手动触发）
    ↓ 从 Apollo 读取配置
    ↓ 构建 Docker 镜像推送到 Harbor
    ↓ kubectl apply（Deployment + Service + Ingress）
    ↓ 等待 Pod Ready
    ✅ 访问 http://<appDomain>
```

---

## 验证

Pipeline 成功后：

```bash
# 查看 Pod 状态
SSH_CMD "kubectl get pods -n fat -l app=<app-id>"

# 测试访问
curl http://<appDomain>/actuator/health    # Java
curl http://<appDomain>                   # 前端
curl http://<appDomain>/health            # Python
```

Pipeline 日志中可直接看到：
- Apollo 读取的配置值
- Docker 镜像 tag
- kubectl apply 结果
- 钉钉通知（如已配置）

---

## 常见问题

| 现象 | 原因 | 解决 |
|------|------|------|
| `无法从 Apollo 获取配置` | AppId 不存在或 tech.common 未关联 | Apollo Portal 创建 AppId 并关联 namespace |
| `limits < requests，Pod 无法创建` | `appMemoryLimit` 低于 256（Python）或 `appCpuLimit` 低于 0.2 | 调高配置值 |
| `ImagePullBackOff` | Harbor 密钥未创建或密码错误 | 检查 `kubectl get secret harbor-registry -n fat` |
| `Ingress 不可达` | Traefik 未配置或 DNS 未解析到 Traefik IP | 检查 `kubectl get ingress -n fat` 和 dnsmasq |
| `jar stage 失败` | Maven 编译错误或 Nexus 不可达 | 查看 Pipeline 日志，检查 `pom.xml` 依赖 |
| `HPA 不生效` | `k8sReplicasMin` / `k8sReplicasMax` 未同时配置 | 确认两项均已在 Apollo 配置并发布 |
| `PDB 阻塞 drain` | `k8sPdbMinAvailable >= k8sReplicas` | 降低 PDB 值或升高副本数 |

---

## 版本对应关系

| 业务框架 | 版本 | 对应基础设施 |
|---------|------|-------------|
| JDK | 21 | 所有 Java 服务 |
| Spring Boot | 3.5.x | MySQL 8.4, Redis 8.0, MongoDB 8.0 |
| Spring Cloud | 2025.0.0 (Northfields) | Consul 1.20 |
| Apollo Client (apollo-java) | 2.4.0 | Apollo 2.5.0 |
| Redisson | 4.3.0 | Redis 8.0 |
| Spring AMQP | 4.x | RabbitMQ 4.0 |
| Spring Data MongoDB | 4.4.x | MongoDB 8.0 |
| Micrometer Tracing | 1.4.x | OpenTelemetry + Tempo 2.7 |
| OpenTelemetry SDK | 1.45+ | OTel Collector 0.120, Tempo 2.7, Loki 3.5 |
| Micrometer Prometheus | - | Prometheus 3.2 + Grafana 11.4 |
