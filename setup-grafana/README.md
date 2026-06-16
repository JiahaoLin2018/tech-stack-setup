# setup-grafana — Grafana 统一可视化看板部署工具

使用 Docker Compose 部署 Grafana 11.4 统一可视化看板，预配置 Prometheus/Tempo/Loki 三大数据源，实现 Metrics/Traces/Logs 三支柱统一查询与关联跳转，支持本地和远程两种部署模式。

## B 类 --env 契约

本 Skill 支持 `--env nonprod|prod` 参数，部署两套独立实例：

| 环境 | 说明 | 部署目录 | 容器名 | Web UI 域名 |
|------|------|---------|--------|-------------|
| `nonprod` | 非生产共用（默认） | `/opt/tech-stack/grafana-nonprod/` | `tech-grafana-nonprod` | `grafana-nonprod-ui.renew.com` |
| `prod` | 生产独立 | `/opt/tech-stack/grafana-prod/` | `tech-grafana-prod` | `grafana-prod-ui.renew.com` |

## 安装

```bash
bash setup-grafana/install.sh
```

脚本将 `setup-grafana/` 全部内容复制到 `~/.claude/skills/setup-grafana/`。

## 目录结构

```
setup-grafana/
├── SKILL.md                                  # 路由指令（Claude 读取）
├── actions/
│   ├── start.md                              # 启动流程（本地 + 远程）
│   ├── stop.md                               # 停止服务
│   ├── status.md                             # 运行状态
│   ├── verify.md                             # 服务验证 + 数据源检查 + Dashboard 导入说明
│   └── logs.md                               # 日志查看与排查
├── references/
│   ├── docker-compose.yml                    # 生产级 Compose 配置
│   ├── .env.example                          # 环境变量模板
│   ├── pitfalls.md                           # 踩坑记录
│   └── conf/
│       └── grafana/
│           └── provisioning/
│               ├── datasources/datasources.yml  # 数据源配置（Prometheus+Tempo+Loki）
│               └── dashboards/dashboards.yml    # Dashboard 目录配置
├── README.md
└── install.sh
```

## 快速使用

```
/setup-grafana                               # 本地启动（默认 start）
/setup-grafana start                         # 本地启动
/setup-grafana stop                          # 本地停止
/setup-grafana status                        # 查看状态
/setup-grafana verify                        # 验证服务 + 数据源检查
/setup-grafana logs                          # 查看日志

# 远程部署（密码认证）
/setup-grafana start --host <HOST> --user ubuntu --password mypass

# 远程部署（密钥认证）
/setup-grafana start --host <HOST> --user ubuntu --key ~/.ssh/id_rsa
```

## 服务端口

| 服务 | 端口 | 说明 |
|------|------|------|
| Grafana | 3000 | 统一可视化 Dashboard（需认证） |

## 工作目录

- **nonprod**：`/opt/tech-stack/grafana-nonprod/`
- **prod**：`/opt/tech-stack/grafana-prod/`

首次 `start` 时自动从 `references/` 复制配置模板到工作目录，**不会覆盖已有的 `.env`**。

## 预配置数据源

Grafana 已预配置三个数据源（通过 `provisioning/datasources/` 自动注入）：

| 数据源 | 类型 | 地址 | 用途 |
|--------|------|------|------|
| Prometheus | prometheus | `http://prometheus-{env}.renew.com:9090` | 指标查询（默认） |
| Tempo | tempo | `http://tempo-{env}.renew.com:3200` | 链路追踪查询（TraceQL） |
| Loki | loki | `http://loki-{env}.renew.com:3100` | 日志查询（LogQL） |

> 部署 `setup-prometheus`（Prometheus）、`setup-tempo` 和 `setup-loki` 后，Grafana 可直接使用 Explore 面板查询。
> 已配置 Trace ↔ Log 双向跳转：日志中包含 `traceId` 字段时，点击即可跳转到对应的链路详情。

## 跨机数据源配置

当 Prometheus、Tempo 或 Loki 部署在不同机器时，修改 `.env` 中的地址变量：

```bash
# /opt/tech-stack/grafana-{env}/.env
PROMETHEUS_HOST=prometheus-{env}.renew.com  # 或直接使用 IP
PROMETHEUS_PORT=9090
TEMPO_HOST=tempo-{env}.renew.com
TEMPO_PORT=3200
LOKI_HOST=loki-{env}.renew.com
LOKI_PORT=3100
```

启动时会自动替换 Grafana 数据源配置中的地址。

## 推荐 Dashboard

| Dashboard | ID | 说明 |
|-----------|-----|------|
| JVM (Micrometer) | 4701 | JVM 核心指标 |
| Spring Boot 统计 | 12900 | HTTP 请求与性能 |
| MySQL Overview | 7362 | MySQL 性能监控 |
| Redis Dashboard | 11835 | Redis 运行状态 |

---

## Spring Boot 可观测性集成

Grafana 透明支持 Spring Boot 两种 OTel 接入方案：

| 方案 | 适用版本 | 接入方式 |
|------|---------|---------|
| 方案 A (Bridge) | Spring Boot 3.x + JDK 17+ | pom 依赖 + Micrometer OTel Bridge |
| 方案 B (Agent) | Spring Boot 2.x 或 JDK < 17 | OTel Java Agent 字节码注入 |

两方案输出统一的 OTLP 格式，Grafana 通过三数据源（Prometheus/Tempo/Loki）和三组跳转配置（Trace↔Log、Trace→Metrics）实现跨支柱关联查询。

### 架构总览

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    Spring Boot 可观测性全链路架构                                 │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  应用层：Spring Boot Pod                                                 │   │
│  │                                                                         │   │
│  │  ┌────────────────────────────┐    ┌────────────────────────────┐      │   │
│  │  │  方案 A: Bridge (SB 3.x)   │    │  方案 B: Agent (SB 2.x)    │      │   │
│  │  │                            │    │                            │      │   │
│  │  │  pom 依赖:                 │    │  JAVA_OPTS:               │      │   │
│  │  │  - micrometer-bridge-otel  │    │  -javaagent:otel.jar      │      │   │
│  │  │  - otlp-exporter           │    │                            │      │   │
│  │  │  - otel-logback-appender   │    │  字节码自动注入埋点         │      │   │
│  │  │                            │    │                            │      │   │
│  │  │  Metrics: Actuator         │    │  Metrics: Actuator         │      │   │
│  │  │  Traces:  OTel SDK ─OTLP─→ │    │  Traces:  Agent ─OTLP─→    │      │   │
│  │  │  Logs:    OTel Appender ─→ │    │  Logs:    Agent 桥接 ─→    │      │   │
│  │  └────────────────────────────┘    └────────────────────────────┘      │   │
│  │                                                                         │   │
│  │  环境标识（两方案相同）:                                                  │   │
│  │    OTEL_RESOURCE_ATTRIBUTES=deployment.environment={env}               │   │
│  │    OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-{env}.renew.com:4317        │   │
│  │    OTEL_METRICS_EXPORTER=none  # Metrics 走 Prometheus 拉取             │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                          │
│                                      ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  采集层：OTel Collector (otel-{env}.renew.com:4317)                     │   │
│  │                                                                         │   │
│  │    OTLP 接收 → 透传 deployment.environment → 分发                       │   │
│  │    Traces ──→ Tempo     Logs ──→ Loki                                  │   │
│  │    Metrics 不经过 Collector（Prometheus 直接拉取）                        │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                          │
│                                      ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  存储层（三支柱）                                                        │   │
│  │                                                                         │   │
│  │  Prometheus              Tempo                  Loki                    │   │
│  │  指标 + env 标签         链路 + env 属性        日志 + env 标签          │   │
│  │  (relabel 附加)          (SDK/Agent 注入)       (SDK/Agent 注入)         │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                          │
│                                      ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  可视化层：Grafana (grafana-{env}-ui.renew.com)                         │   │
│  │                                                                         │   │
│  │  三数据源: Prometheus / Tempo / Loki                                    │   │
│  │  三跳转:   Trace↔Log / Trace→Metrics                                   │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 双方案对比

| 维度 | 方案 A (Bridge) | 方案 B (Agent) |
|------|----------------|----------------|
| **适用版本** | Spring Boot 3.x + JDK 17+ | Spring Boot 2.x 或 JDK < 17 |
| **接入方式** | pom 依赖 + 配置 | Agent jar 由 K8s volumes 挂载到 `/opt/otel/` + 启动参数 |
| **埋点技术** | 代码级 API 调用 | 字节码注入 |
| **代码可见性** | 依赖在 pom，可自定义埋点 | 完全无感 |
| **启动开销** | 无额外开销 | +300~800ms 启动，+30~80MB 内存 |
| **GraalVM Native** | 支持 | 不支持 |
| **指标来源** | Micrometer Prometheus Registry | 同左（需关闭 Agent 指标导出） |

**方案选择流程**：

```
Spring Boot 版本 ≥ 3.0 && JDK ≥ 17?
    │
    ├── 是 → 方案 A (Micrometer + Bridge) — 推荐 ★
    │
    └── 否 → 方案 B (Java Agent) — 兜底方案
```

### 数据通路详解

#### Metrics 通路（两方案相同）

```
Spring Boot Pod                              独立服务器
┌─────────────────────────────┐             ┌──────────────────┐
│  Actuator                   │             │  Prometheus      │
│  /actuator/prometheus       │  ←──拉取──  │  consul_sd 发现  │
│                             │             │  + relabel 附加  │
│  暴露指标:                   │             │    env={namespace}│
│  http_server_requests_*     │             │                  │
│  jvm_memory_used_*          │             │                  │
└─────────────────────────────┘             └──────────────────┘
```

**关键点**：
- Metrics 不经过 OTel Collector，由 Prometheus 直接拉取
- `env` 标签由 Prometheus `relabel_configs` 附加，应用本身不注入
- 两方案的 `/actuator/prometheus` 格式完全相同（Micrometer 标准）

#### Traces 通路

```
方案 A (Bridge)                              独立服务器
┌─────────────────────────────┐             ┌──────────────────┐
│  Micrometer Tracing         │             │  OTel Collector  │
│      ↓ Bridge               │   OTLP      │      ↓           │
│  OTel SDK                   │  ──推送──→  │  Tempo           │
│      ↓                      │             │                  │
│  deployment.environment=fat │             │  按 env 属性存储  │
└─────────────────────────────┘             └──────────────────┘

方案 B (Agent)                               独立服务器
┌─────────────────────────────┐             ┌──────────────────┐
│  OTel Java Agent            │             │  OTel Collector  │
│  字节码注入埋点              │   OTLP      │      ↓           │
│      ↓                      │  ──推送──→  │  Tempo           │
│  deployment.environment=fat │             │                  │
└─────────────────────────────┘             └──────────────────┘
```

**关键点**：
- 两方案都输出标准 OTLP 格式
- `deployment.environment` 由 `OTEL_RESOURCE_ATTRIBUTES` 环境变量注入
- TraceID 格式统一（OTLP 标准）

#### Logs 通路

```
方案 A (Bridge)                              独立服务器
┌─────────────────────────────┐             ┌──────────────────┐
│  Logback                    │             │  OTel Collector  │
│      ↓ OTel Appender        │   OTLP      │      ↓           │
│  OTLP 输出                  │  ──推送──→  │  Loki            │
│      ↓                      │             │                  │
│  traceId + deployment.env   │             │  按 env 标签存储  │
└─────────────────────────────┘             └──────────────────┘

方案 B (Agent)                               独立服务器
┌─────────────────────────────┐             ┌──────────────────┐
│  Logback                    │             │  OTel Collector  │
│      ↓ Agent 桥接注入       │   OTLP      │      ↓           │
│  OTLP 输出                  │  ──推送──→  │  Loki            │
│      ↓                      │             │                  │
│  traceId + deployment.env   │             │  按 env 标签存储  │
└─────────────────────────────┘             └──────────────────┘
```

**关键点**：
- 两方案的日志格式统一（OTLP 标准）
- 日志中 `traceId` 字段格式相同，支持 Trace ↔ Log 双向跳转

### Grafana 跨支柱关联

#### 数据源配置

| 数据源 | UID | 存储组件 | 查询方式 |
|--------|-----|---------|---------|
| Prometheus | `prometheus` | Prometheus | PromQL |
| Tempo | `tempo` | Tempo | TraceQL |
| Loki | `loki` | Loki | LogQL |

#### 跳转关系

```
┌──────────────┐    tracesToLogsV2     ┌──────────────┐
│    Tempo     │ ─────────────────────→│     Loki     │
│   (Traces)   │   datasourceUid:loki  │    (Logs)    │
│              │   filterByTraceID     │              │
│              │←─────────────────────│              │
└──────────────┘    derivedFields     └──────────────┘
       │           datasourceUid:tempo
       │
       │ tracesToMetrics / serviceMap
       │ datasourceUid: prometheus
       ▼
┌──────────────┐
│  Prometheus  │
│  (Metrics)   │
└──────────────┘
```

#### 为什么双方案兼容

| 层级 | 方案 A (Bridge) | 方案 B (Agent) | Grafana 影响 |
|------|----------------|----------------|-------------|
| **埋点方式** | pom 依赖 + 代码 API | 字节码注入 | ❌ 不影响 |
| **OTLP 格式** | 标准 OTLP | 标准 OTLP | ❌ 不影响 |
| **TraceID 格式** | OTLP 标准 | OTLP 标准 | ❌ 不影响 |
| **Metrics 格式** | Micrometer 标准 | Micrometer 标准 | ❌ 不影响 |
| **env 标签来源** | SDK 读取环境变量 | Agent 读取环境变量 | ❌ 不影响 |
| **存储位置** | Prometheus/Tempo/Loki | Prometheus/Tempo/Loki | ❌ 不影响 |
| **Grafana 查询** | 统一查询接口 | 统一查询接口 | ✅ **完全相同** |

**核心结论**：OTLP 协议标准化将埋点技术差异封装在应用层，Grafana 只需对接标准存储后端即可透明支持双方案。

### Grafana 查询示例

#### 按环境过滤

```promql
# Prometheus (Metrics) - 仅查看 FAT 环境的 HTTP 请求速率
rate(http_server_requests_seconds_count{env="fat"}[5m])

# 对比各环境的 P99 延迟
histogram_quantile(0.99, rate(http_server_requests_seconds_bucket[5m])) by (env)
```

```
# Tempo (TraceQL) - 仅查看 FAT 环境 500+ 错误
{resource.deployment.environment="fat" && span.http.status_code>=500}

# 查看特定服务的链路
{resource.deployment.environment="fat" && resource.service.name="loan-service"}
```

```logql
# Loki (LogQL) - 仅查看 FAT 环境错误日志
{deployment_environment="fat", service_name="loan-service"} |= "ERROR"

# 对比 FAT 和 UAT 环境
{deployment_environment=~"fat|uat", service_name="risk-service"} |= "exception"
```

#### 跨支柱追踪

1. **从 Metrics 发现异常**：Dashboard 显示 `http_server_requests_seconds_count{env="fat",status="500"}` 上升
2. **跳转到 Traces**：点击数据点 → Explore → 查看对应时间段的 Trace
3. **跳转到 Logs**：在 Trace 详情页点击 "Logs for this span" → 查看相关日志
4. **反向追踪**：从日志中点击 TraceID 链接 → 跳转到对应链路

---

## 相关文档

| 文档 | 说明 |
|------|------|
| [踩坑记录](references/pitfalls.md) | 部署问题历史存档 |
| 架构蓝图 | `observability-env-isolation.md` — LGT 栈 env 标签逻辑隔离完整设计 |
| Spring Boot 接入指南 | `setup-cicd/actions/integrate.md` — 双方案 pom 依赖与配置详解 |
