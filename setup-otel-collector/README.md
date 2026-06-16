# setup-otel-collector — OpenTelemetry Collector 统一可观测性网关部署工具

使用 Docker Compose 部署 OpenTelemetry Collector Contrib v0.120.0，作为统一可观测性数据接收网关，接收应用通过 OTLP 协议发送的 Traces 和 Logs，路由至 Tempo/Loki 后端，支持本地和远程两种部署模式。

> **Metrics 说明**：应用指标通过 `/actuator/prometheus` 暴露，由 Prometheus 直接拉取，不经过 OTel Collector。

## B 类 --env 契约

本 Skill 支持 `--env nonprod|prod` 参数，部署两套独立实例：

| 环境 | 说明 | 部署目录 | 容器名 | 域名 |
|------|------|---------|--------|------|
| `nonprod` | 非生产共用（默认） | `/opt/tech-stack/otel-collector-nonprod/` | `tech-otel-collector-nonprod` | `otel-nonprod.renew.com` |
| `prod` | 生产独立 | `/opt/tech-stack/otel-collector-prod/` | `tech-otel-collector-prod` | `otel-prod.renew.com` |

## 架构概览

```
                        ┌─────────────────────────────┐
  App A ──OTLP──►       │   OpenTelemetry Collector    │
  App B ──OTLP──►       │     (tech-otel-collector)    │
  App C ──OTLP──►       │                             │
                        │  ┌─────────┐                │
  gRPC :4317 ──────────►│  │ otlp    │                │
  HTTP :4318 ──────────►│  │receiver │                │
                        │  └────┬────┘                │
                        │       │                     │
                        │  ┌────▼────────────┐        │
                        │  │ memory_limiter   │        │
                        │  │ batch            │        │
                        │  │ resource         │        │
                        │  └────┬────────────┘        │
                        │       │                     │
                        │  ┌────▼────────────────┐    │
                        │  │ Traces  → Tempo     │    │
                        │  │ Logs    → Loki      │    │
                        │  └─────────────────────┘    │
                        └─────────────────────────────┘

  App Metrics ─────────────────────────────────────► Prometheus（直接拉取 /actuator/prometheus）
```

## 安装

```bash
bash setup-otel-collector/install.sh
```

脚本将 `setup-otel-collector/` 全部内容复制到 `~/.claude/skills/setup-otel-collector/`。

## 目录结构

```
setup-otel-collector/
├── SKILL.md                                  # 路由指令（Claude 读取）
├── actions/
│   ├── start.md                              # 启动流程（本地 + 远程）
│   ├── stop.md                               # 停止服务
│   ├── status.md                             # 运行状态
│   ├── verify.md                             # 服务验证 + OTLP 连通性测试
│   └── logs.md                               # 日志查看与排查
├── references/
│   ├── docker-compose.yml                    # 生产级 Compose 配置
│   ├── .env.example                          # 环境变量模板
│   └── conf/
│       └── otel-collector-config.yml.tpl     # Collector 管道路由配置模板
├── README.md
└── install.sh
```

## 快速使用

```
/setup-otel-collector                               # 本地启动（默认 start）
/setup-otel-collector start                         # 本地启动
/setup-otel-collector stop                          # 本地停止
/setup-otel-collector status                        # 查看状态
/setup-otel-collector verify                        # 验证服务 + OTLP 连通性
/setup-otel-collector logs                          # 查看日志

# 远程部署（密码认证）
/setup-otel-collector start --host <HOST> --user ubuntu --password mypass

# 远程部署（密钥认证）
/setup-otel-collector start --host <HOST> --user ubuntu --key ~/.ssh/id_rsa
```

## 服务端口

| 端口 | 协议 | 说明 |
|------|------|------|
| 4317 | gRPC | OTLP gRPC 接收端 — 应用发送 Traces/Logs |
| 4318 | HTTP | OTLP HTTP 接收端 — 应用发送 Traces/Logs |
| 8888 | HTTP | Collector 自身运行指标（Prometheus 采集） |
| 13133 | HTTP | 健康检查端点（容器内部，未映射到宿主机） |

## 工作目录

- **nonprod**：`/opt/tech-stack/otel-collector-nonprod/`
- **prod**：`/opt/tech-stack/otel-collector-prod/`

首次 `start` 时自动从 `references/` 复制配置模板到工作目录，**不会覆盖已有的 `.env`**。

## 配置说明

### 环境变量（.env）

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `ENV` | `nonprod` | 部署环境（nonprod/prod） |
| `OTEL_GRPC_PORT` | 4317 | OTLP gRPC 接收端口 |
| `OTEL_HTTP_PORT` | 4318 | OTLP HTTP 接收端口 |
| `OTEL_METRICS_PORT` | 8888 | Collector 自身指标端口（Prometheus 采集用） |
| `TEMPO_HOST` | `tempo-nonprod.renew.com` | Tempo 后端地址（prod 时改为 `tempo-prod.renew.com`） |
| `TEMPO_GRPC_PORT` | 14317 | Tempo OTLP gRPC 宿主机端口 |
| `LOKI_HOST` | `loki-nonprod.renew.com` | Loki 后端地址（prod 时改为 `loki-prod.renew.com`） |
| `LOKI_PORT` | 3100 | Loki HTTP 端口 |
| `DEPLOYMENT_ENV` | `nonprod` | 注入的部署环境标识（prod 时改为 `prod`） |
| `OTEL_MEMORY_LIMIT` | 512m | 容器内存限制 |

### 后端地址配置

默认使用 `{service}-{env}.renew.com` 域名（如 `tempo-nonprod.renew.com`、`loki-prod.renew.com`），通过 dnsmasq 统一寻址，单机和跨机配置一致。

## 管道架构

OTel Collector 配置了两条独立管道：

| 管道 | 接收器 | 处理器 | 导出器 | 目标 |
|------|--------|--------|--------|------|
| traces | otlp | memory_limiter → batch → resource | otlp/tempo | Tempo :14317 |
| logs | otlp | memory_limiter → batch → resource | otlphttp/loki | Loki :3100/otlp |

### 处理器说明

- **memory_limiter**: 限制内存使用 400 MiB，峰值 100 MiB，防止 OOM
- **batch**: 批量发送，每批 1024 条，超时 5 秒
- **resource**: 对 `deployment.environment` 属性使用 `action: insert`——仅在数据中不存在时才插入兜底值 `${DEPLOYMENT_ENV}`（nonprod/prod）；应用通过 `OTEL_RESOURCE_ATTRIBUTES=deployment.environment={env}` 传入的具体环境值（dev/sit/fat/uat/prod）会被原样保留

## Spring Boot 接入指南

> 详见 `observability-env-isolation.md` 第 6 节完整说明。

### 方案 A：Micrometer Observation + OTel Bridge（Spring Boot 3.x 主力方案）★

Spring Boot 3.x 新项目推荐使用 Micrometer + Bridge 方案，指标单一来源、云原生标准化。

```yaml
# application.yml
management:
  otlp:
    tracing:
      endpoint: http://otel-{env}.renew.com:4317
  tracing:
    sampling:
      probability: 1.0
```

关键环境变量（由 app.sh 自动注入）：
- `OTEL_SERVICE_NAME={appId}`
- `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-{domainEnv}.renew.com:4317`
- `OTEL_RESOURCE_ATTRIBUTES=deployment.environment={env},service.namespace={env}`
- `OTEL_METRICS_EXPORTER=none` — 固定为 none，Metrics 由 Prometheus 直接拉取 `/actuator/prometheus`，不走 OTLP 通路
- `OTEL_LOGS_EXPORTER=otlp`
- `OTEL_TRACES_EXPORTER=otlp`

> **为什么 OTEL_METRICS_EXPORTER 固定为 none？**
> - 方案 A（Bridge）：OTel SDK 默认不产生 Metrics，但显式设为 none 明确声明"Metrics 不走 OTLP"
> - 方案 B（Agent）：**必须设为 none**，否则 Agent 会产生 `http.server.duration` 等指标，与 Actuator 的 `http_server_requests_seconds_*` 重复冲突

> **domainEnv 映射**：dev/sit/fat/uat → `nonprod`，prod → `prod`

### 方案 B：OpenTelemetry Java Agent（Spring Boot 2.x 兜底方案）

仅用于 Spring Boot 2.x 老系统或 JDK < 17 的场景。

```bash
java -javaagent:/opt/otel/opentelemetry-javaagent.jar \
  -Dotel.exporter.otlp.endpoint=http://otel-{env}.renew.com:4317 \
  -Dotel.service.name=my-service \
  -Dotel.resource.attributes=deployment.environment={env} \
  -Dotel.metrics.exporter=none \
  -Dotel.instrumentation.micrometer.enabled=false \
  -jar app.jar
```

> **注意**：方案 B 必须设置 `OTEL_METRICS_EXPORTER=none` 和 `OTEL_INSTRUMENTATION_MICROMETER_ENABLED=false`，避免与 Actuator 指标重复。

## 与 Tempo 的端口协调

OTel Collector 和 Tempo 使用不同的宿主机端口避免冲突：

- **OTel Collector** 占用宿主机 4317/4318（应用发送数据的入口）
- **Tempo** 使用宿主机 14317/14318 接收 OTLP（OTel Collector 通过 `tempo-{env}.renew.com:14317` 转发 traces）

如果未部署 OTel Collector，可将 Tempo 的 `TEMPO_OTLP_GRPC_PORT` 改为 4317 直接接收。

## 跨机部署

当后端服务（Tempo/Loki）部署在不同机器时：

```bash
# 修改 .env（使用 ② 域级直连域名，已在 setup-dns hosts.lan 中映射）
TEMPO_HOST=tempo-nonprod.renew.com   # prod 实例改为 tempo-prod.renew.com
TEMPO_GRPC_PORT=14317
LOKI_HOST=loki-nonprod.renew.com     # prod 实例改为 loki-prod.renew.com
LOKI_PORT=3100
```

启动时会自动将 `otel-collector-config.yml` 中的默认地址替换为配置的地址，并检测后端可达性。

## 可观测性数据流总结

| 数据类型 | 应用发送方式 | 路径 | 最终存储 |
|---------|------------|------|---------|
| **Traces** | OTLP → `otel-{env}.renew.com:4317/4318` | OTel Collector → `tempo-{env}.renew.com:14317` | Tempo |
| **Logs** | OTLP → `otel-{env}.renew.com:4317/4318` | OTel Collector → `loki-{env}.renew.com:3100/otlp` | Loki |
| **Metrics** | 暴露 `/actuator/prometheus` | Prometheus 直接拉取 | Prometheus |
