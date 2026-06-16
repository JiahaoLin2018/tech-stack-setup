# setup-loki — Grafana Loki 日志聚合系统部署工具

使用 Docker Compose 部署 Grafana Loki 3.5 日志聚合系统，提供轻量级日志收集、标签索引和 LogQL 查询能力，可替代 ELK Stack 用于日志场景，支持本地和远程两种部署模式。

## B 类 --env 契约

本 Skill 支持 `--env nonprod|prod` 参数，部署两套独立实例：

| 环境 | 说明 | 部署目录 | 容器名 | 域名 |
|------|------|---------|--------|------|
| `nonprod` | 非生产共用（默认） | `/opt/tech-stack/loki-nonprod/` | `tech-loki-nonprod` | `loki-nonprod.renew.com` |
| `prod` | 生产独立 | `/opt/tech-stack/loki-prod/` | `tech-loki-prod` | `loki-prod.renew.com` |

## 概述

Loki 是 Grafana Labs 开源的日志聚合系统，设计理念为 "like Prometheus, but for logs"。与 ELK 不同，Loki 只索引日志的标签（labels）而非全文，因此资源消耗极低，非常适合中小团队和资源受限场景。

核心优势：
- 资源占用低（对比 Elasticsearch 降低 10 倍以上内存需求）
- 与 Grafana 原生集成，Metrics + Logs 统一查看
- LogQL 查询语法类似 PromQL，学习成本低
- 支持多租户、数据保留策略和自动压缩

## 安装

```bash
bash setup-loki/install.sh
```

脚本将 `setup-loki/` 全部内容复制到 `~/.claude/skills/setup-loki/`。

## 目录结构

```
setup-loki/
├── SKILL.md                           # 路由指令（Claude 读取）
├── actions/
│   ├── start.md                       # 启动流程（本地 + 远程）
│   ├── stop.md                        # 停止服务
│   ├── status.md                      # 运行状态
│   ├── verify.md                      # 服务验证 + LogQL 示例
│   └── logs.md                        # 日志查看与排查
├── references/
│   ├── docker-compose.yml             # 生产级 Compose 配置
│   ├── .env.example                   # 环境变量模板
│   └── conf/
│       └── loki-config.yml.tpl        # Loki 存储与保留配置模板
├── README.md
└── install.sh
```

## 快速使用

```
/setup-loki                               # 本地启动（默认 start）
/setup-loki start                         # 本地启动
/setup-loki stop                          # 本地停止
/setup-loki status                        # 查看状态
/setup-loki verify                        # 验证服务 + LogQL 示例
/setup-loki logs                          # 查看日志

# 远程部署（密码认证）
/setup-loki start --host <HOST> --user ubuntu --password mypass

# 远程部署（密钥认证）
/setup-loki start --host <HOST> --user ubuntu --key ~/.ssh/id_rsa
```

## 服务端口

| 服务 | 端口 | 说明 |
|------|------|------|
| Loki HTTP API | 3100 | 日志推送、查询、健康检查 |

## 工作目录

- **nonprod**：`/opt/tech-stack/loki-nonprod/`
- **prod**：`/opt/tech-stack/loki-prod/`

首次 `start` 时自动从 `references/` 复制配置模板到工作目录，**不会覆盖已有的 `.env`**。

## 配置（.env 变量）

所有运行时可调参数统一在 `.env` 中管理，通过 `-config.expand-env=true` 注入到 `loki-config.yml`。

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `LOKI_AUTH_ENABLED` | `false` | 多租户认证开关（生产环境必须设为 `true`） |
| `LOKI_PORT` | 3100 | Loki HTTP API 端口 |
| `LOKI_GRPC_PORT` | 9096 | Loki gRPC 端口（集群通信 / 内部调用） |
| `LOKI_RETENTION_PERIOD` | 168h | 数据保留时间（7 天） |
| `LOKI_COMPACTION_INTERVAL` | 10m | Compactor 压缩间隔 |
| `LOKI_RETENTION_DELETE_DELAY` | 2h | 保留删除延迟（防止误删查询中数据） |
| `LOKI_INGESTION_RATE_MB` | 10 | 每租户每秒摄入速率上限（MB） |
| `LOKI_INGESTION_BURST_SIZE_MB` | 20 | 摄入突发大小（MB） |
| `LOKI_MAX_STREAMS_PER_USER` | 10000 | 每租户最大活跃日志流数 |
| `LOKI_MAX_QUERY_SERIES` | 500 | 单次查询最大返回序列数 |
| `LOKI_CACHE_MAX_SIZE_MB` | 100 | 查询结果缓存大小（MB） |
| `LOKI_MEMORY_LIMIT` | 1g | 容器内存上限 |
| `LOKI_LOG_LEVEL` | info | 服务端日志级别（debug / info / warn / error） |

修改 `.env` 后需重启容器生效：`cd /opt/tech-stack/loki && docker compose restart`

## Spring Boot 接入

Loki 通过 OTel Collector 接收日志，支持两种 Spring Boot 接入方案，两方案共用同一套 Loki 后端配置。

### 整体架构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Spring Boot 日志接入 Loki — 双方案架构                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  方案 A (SB 3.x 主力)                   方案 B (SB 2.x 兜底)                 │
│  ┌─────────────────────────┐           ┌─────────────────────────┐         │
│  │  Spring Boot 3.x        │           │  Spring Boot 2.x        │         │
│  │                         │           │                         │         │
│  │  opentelemetry-         │           │  Java Agent 字节码注入   │         │
│  │  logback-appender-1.0   │           │  (jar 由 volumes 挂载)   │         │
│  │  (pom 显式依赖)          │           │  无需修改代码            │         │
│  └───────────┬─────────────┘           └───────────┬─────────────┘         │
│              │                                     │                        │
│              │  OTLP 推送                           │  OTLP 推送             │
│              │  env 由 SDK 读取                     │  env 由 Agent 读取     │
│              │  OTEL_RESOURCE_ATTRIBUTES           │  OTEL_RESOURCE_        │
│              │  =deployment.environment={env}      │  ATTRIBUTES=...        │
│              ▼                                     ▼                        │
│  ┌───────────────────────────────────────────────────────────────────┐     │
│  │                      OTel Collector                                │     │
│  │                      :4317 (gRPC) / :4318 (HTTP)                   │     │
│  │                                                                    │     │
│  │  exporters:                                                        │     │
│  │    otlphttp/loki:                                                  │     │
│  │      endpoint: "http://loki-{env}.renew.com:3100/otlp"            │     │
│  └───────────────────────────────────────────────────────────────────┘     │
│                                        │                                   │
│                                        ▼                                   │
│  ┌───────────────────────────────────────────────────────────────────┐     │
│  │                          Loki 3.5                                  │     │
│  │                          :3100/otlp                                │     │
│  │                                                                    │     │
│  │  limits_config:                                                    │     │
│  │    allow_structured_metadata: true                                 │     │
│  │    otlp_config:                                                    │     │
│  │      resource_attributes:                                          │     │
│  │        attributes_config:                                          │     │
│  │          - action: index_label                                     │     │
│  │            attributes:                                             │     │
│  │              - service.name          → service_name 标签           │     │
│  │              - deployment.environment → deployment_environment 标签 │     │
│  └───────────────────────────────────────────────────────────────────┘     │
│                                                                             │
│  关键设计：Loki 不关心日志来源是 Bridge 还是 Agent，只认 OTLP 格式           │
│            两方案通过统一的 OTel Collector 转发，标签体系完全一致             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 方案对比

| 维度 | 方案 A：Micrometer + OTel Bridge | 方案 B：Java Agent |
|------|--------------------------------|-------------------|
| **适用版本** | Spring Boot 3.x + JDK 17+ | Spring Boot 2.x / JDK < 17 |
| **接入方式** | pom 依赖 + logback 配置 | Agent jar 由 K8s volumes 挂载到 `/opt/otel/` + `-javaagent` 参数 |
| **代码侵入** | 需添加依赖和配置 | 无需修改代码 |
| **日志出口** | `opentelemetry-logback-appender-1.0` | Agent 自动注入 Logback 桥接 |
| **env 标签来源** | SDK 读取 `OTEL_RESOURCE_ATTRIBUTES` | Agent 读取 `OTEL_RESOURCE_ATTRIBUTES` |
| **Loki 接收** | OTLP 格式 | OTLP 格式（完全相同） |

### 方案 A：Micrometer + OTel Bridge（SB 3.x 主力）

**pom.xml 依赖**：

```xml
<dependency>
    <groupId>io.opentelemetry.instrumentation</groupId>
    <artifactId>opentelemetry-logback-appender-1.0</artifactId>
</dependency>
```

**logback-spring.xml 配置**：

```xml
<appender name="OTEL" class="io.opentelemetry.instrumentation.logback.appender.v1_0.OpenTelemetryAppender">
    <captureExperimentalAttributes>true</captureExperimentalAttributes>
    <captureCodeAttributes>true</captureCodeAttributes>
    <captureMdcAttributes>*</captureMdcAttributes>
</appender>

<root level="INFO">
    <appender-ref ref="CONSOLE"/>
    <appender-ref ref="OTEL"/>
</root>
```

**环境变量**（由 app.sh 注入）：

```yaml
env:
  - name: OTEL_SERVICE_NAME
    value: "{appId}"
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-{domainEnv}.renew.com:4317"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "deployment.environment={env},service.namespace={env}"
  - name: OTEL_LOGS_EXPORTER
    value: "otlp"
```

### 方案 B：Java Agent（SB 2.x 兜底）

**Agent jar 部署方式**：jar 由 `setup-gitlab-runner` 统一管理，存放在宿主机 `/opt/tech-stack/cicd/opentelemetry-javaagent.jar`，通过 K8s Deployment 的 volumes 挂载到 Pod 容器内 `/opt/otel/opentelemetry-javaagent.jar`。业务基础镜像无需预置 Agent。

**启动参数**（由 app.sh 自动注入）：

```bash
JAVA_OPTS="-javaagent:/opt/otel/opentelemetry-javaagent.jar"
```

**环境变量**（与方案 A 相同，由 app.sh 注入）：

```yaml
env:
  - name: OTEL_SERVICE_NAME
    value: "{appId}"
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-{domainEnv}.renew.com:4317"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "deployment.environment={env},service.namespace={env}"
  - name: OTEL_LOGS_EXPORTER
    value: "otlp"
```

### Loki 对两方案的统一处理

无论哪种方案，Loki 接收的都是标准 OTLP 格式日志，处理方式完全相同：

**Loki 配置**（`loki-config.yml.tpl` 已预配置）：

```yaml
limits_config:
  allow_structured_metadata: true    # 必须启用，支持 OTLP 结构化元数据
  otlp_config:
    resource_attributes:
      attributes_config:
        - action: index_label
          attributes:
            - service.name            # → service_name 标签
            - deployment.environment  # → deployment_environment 标签
```

**标签转换规则**：Loki 自动将 OTLP 资源属性中的点号 `.` 转为下划线 `_`

| OTLP 资源属性 | Loki 标签名 |
|--------------|------------|
| `deployment.environment` | `deployment_environment` |
| `service.name` | `service_name` |

### LogQL 查询示例

```logql
# 按 env 查询日志
{deployment_environment="fat", service_name="loan-service"} |= "ERROR"

# 正则匹配多环境
{deployment_environment=~"fat|uat", service_name="risk-service"}

# 按 traceId 关联链路
{service_name="loan-service"} | json | traceId != ""
```

## LogQL 查询示例（通用）

| 查询 | 说明 |
|------|------|
| `{service_name="loan-service"}` | 查看某应用的所有日志 |
| `{service_name="loan-service"} |= "ERROR"` | 按关键字过滤 |
| `{service_name="loan-service"} |~ "timeout|refused"` | 正则匹配 |
| `{service_name="loan-service"} | json | status >= 500` | JSON 解析 + 条件过滤 |
| `rate({service_name="loan-service"} |= "ERROR" [5m])` | 错误速率（5 分钟窗口） |
| `{service_name="loan-service"} | logfmt | duration > 1s` | logfmt 格式慢请求 |
| `topk(10, sum by(service_name) (rate({service_name!=""} [1h])))` | 日志量 Top 10 服务 |

## Grafana 集成

1. 打开 Grafana → Configuration → Data Sources → Add data source
2. 选择 **Loki**
3. URL 填写：`http://loki-{env}.renew.com:3100`（如 `loki-nonprod.renew.com:3100`）
4. 点击 "Save & Test" 验证连接

在 Grafana Explore 页面选择 Loki 数据源即可使用 LogQL 查询日志。

推荐 Dashboard（Grafana -> Dashboards -> Import -> 输入 ID）：

| Dashboard | ID | 说明 |
|-----------|-----|------|
| Loki Operational | 13407 | Loki 运行状态、摄入速率 |
| Loki Dashboard quick search | 12019 | 快速日志搜索面板 |
