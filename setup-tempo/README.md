# setup-tempo — Grafana Tempo 分布式链路追踪部署工具

使用 Docker Compose 部署 Grafana Tempo 2.7 分布式链路追踪后端，支持 OTLP gRPC/HTTP 和 Zipkin 协议接收 Trace 数据，与 Grafana 深度集成实现 TraceQL 查询，支持本地和远程两种部署模式。可替代 SkyWalking 用于 Spring Boot 3.x + JDK 21 场景。

## B 类 --env 契约

本 Skill 支持 `--env nonprod|prod` 参数，部署两套独立实例：

| 环境 | 说明 | 部署目录 | 容器名 | 域名 |
|------|------|---------|--------|------|
| `nonprod` | 非生产共用（默认） | `/opt/tech-stack/tempo-nonprod/` | `tech-tempo-nonprod` | `tempo-nonprod.renew.com` |
| `prod` | 生产独立 | `/opt/tech-stack/tempo-prod/` | `tech-tempo-prod` | `tempo-prod.renew.com` |

## 版本信息

| 组件 | 版本 | 说明 |
|------|------|------|
| Grafana Tempo | 2.7.0 | 分布式链路追踪后端 |
| 配套 Spring Boot | 3.5.x | Micrometer Tracing + OTel Bridge |
| Micrometer Tracing | 1.4.x | Spring Boot 3.x 内置 |
| OpenTelemetry SDK | 1.45+ | OTLP 协议导出 |

## 安装

```bash
bash setup-tempo/install.sh
```

脚本将 `setup-tempo/` 全部内容复制到 `~/.claude/skills/setup-tempo/`。

## 目录结构

```
setup-tempo/
├── SKILL.md                              # 路由指令（Claude 读取）
├── actions/
│   ├── start.md                          # 启动流程（本地 + 远程）
│   ├── stop.md                           # 停止服务
│   ├── status.md                         # 运行状态
│   ├── verify.md                         # 服务验证 + 连通性测试
│   └── logs.md                           # 日志查看与排查
├── references/
│   ├── docker-compose.yml                # 生产级 Compose 配置
│   ├── .env.example                      # 环境变量模板
│   └── conf/
│       └── tempo-config.yml.tpl      # Tempo 配置模板（.env 变量渲染）
├── README.md
└── install.sh
```

## 快速使用

```
/setup-tempo                               # 本地启动（默认 start）
/setup-tempo start                         # 本地启动
/setup-tempo stop                          # 本地停止
/setup-tempo status                        # 查看状态
/setup-tempo verify                        # 验证服务 + 连通性测试
/setup-tempo logs                          # 查看日志

# 远程部署（密码认证）
/setup-tempo start --host <HOST> --user ubuntu --password mypass

# 远程部署（密钥认证）
/setup-tempo start --host <HOST> --user ubuntu --key ~/.ssh/id_rsa
```

## 服务端口

| 端口 | 协议 | 宿主机端口 | 说明 |
|------|------|-----------|------|
| 3200 | HTTP | 3200 | Tempo HTTP API / 健康检查 / TraceQL API |
| 4317 | gRPC | 14317 | OTLP gRPC 接收（OTel Collector 通过 `tempo-{env}.renew.com:14317` 转发） |
| 4318 | HTTP | 14318 | OTLP HTTP 接收（OTel Collector 通过 `tempo-{env}.renew.com:14318` 转发） |
| 9411 | HTTP | 9411 | Zipkin 兼容接收端点（可选） |

**端口说明**：OTLP 宿主机端口使用 14317/14318，避免与同机 OTel Collector 的 4317/4318 冲突。OTel Collector 是应用的唯一 OTLP 入口（占用宿主机 4317/4318），Tempo 通过 `tempo-{env}.renew.com:14317` 接收 OTel Collector 转发的 traces。

## 工作目录

- **nonprod**：`/opt/tech-stack/tempo-nonprod/`
- **prod**：`/opt/tech-stack/tempo-prod/`

首次 `start` 时自动从 `references/` 复制配置模板到工作目录，**不会覆盖已有的 `.env`**。

## 配置说明

### .env 变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `TEMPO_HTTP_PORT` | 3200 | HTTP API 端口 |
| `TEMPO_OTLP_GRPC_PORT` | 14317 | OTLP gRPC 宿主机端口（避免与 OTel Collector 冲突） |
| `TEMPO_OTLP_HTTP_PORT` | 14318 | OTLP HTTP 宿主机端口（避免与 OTel Collector 冲突） |
| `TEMPO_ZIPKIN_PORT` | 9411 | Zipkin 接收端口 |
| `PROMETHEUS_HOST` | prometheus-nonprod.renew.com | Prometheus 地址（prod 时改为 prometheus-prod.renew.com） |
| `PROMETHEUS_PORT` | 9090 | Prometheus 端口 |
| `TEMPO_RETENTION` | 168h | Trace 数据保留时长（7 天） |
| `TEMPO_MEMORY_LIMIT` | 2g | 容器内存限制 |

### 配置渲染机制

`tempo-config.yml.tpl` 是配置模板，启动时通过 `envsubst` 将 `.env` 中的变量（如 `${PROMETHEUS_HOST}`、`${TEMPO_RETENTION}`）渲染为最终的 `tempo-config.yml`。这确保所有可变配置统一在 `.env` 中管理，无需手动编辑 YAML 文件。

### tempo-config.yml 关键配置

- **distributor.receivers**: 配置接收协议（OTLP gRPC/HTTP、Zipkin）
- **compactor.compaction.block_retention**: 数据保留时长（由 `TEMPO_RETENTION` 控制）
- **metrics_generator**: 从 Trace 数据生成 service graph 和 span metrics 指标
- **metrics_generator.storage.remote_write**: 指标推送目标（由 `PROMETHEUS_HOST`:`PROMETHEUS_PORT` 控制）
- **storage.trace**: 存储后端配置（默认本地文件系统）

## Spring Boot 接入方案与 Tempo 的关系

Tempo 作为链路追踪后端，**不区分 traces 来源是哪种接入方案**。无论采用哪种方案，Tempo 只需提供一个 OTLP 接收端口，并原生保留 resource attributes。

### 两种接入方案的统一数据流

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    两种方案最终都输出标准 OTLP 格式                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  方案 A（SB 3.x 主力）                    方案 B（SB 2.x 兜底）              │
│  ┌───────────────────────────────┐       ┌───────────────────────────────┐ │
│  │  Spring Boot 3.x 应用          │       │  Spring Boot 2.x 应用          │ │
│  │                               │       │                               │ │
│  │  Micrometer Tracing           │       │  OTel Java Agent              │ │
│  │       ↓ Bridge                │       │  (字节码注入)                  │ │
│  │  OTel SDK                     │       │       ↓                       │ │
│  └───────────────┬───────────────┘       └───────────────┬───────────────┘ │
│                  │                                       │                 │
│                  │  OTEL_RESOURCE_ATTRIBUTES             │  同左           │
│                  │  =deployment.environment={env}        │                 │
│                  ▼                                       ▼                 │
│                    ┌─────────────────────────┐                           │
│                    │   OTel Collector        │                           │
│                    │   otel-{env}.renew.com  │                           │
│                    │   :4317 (gRPC)          │                           │
│                    │                         │                           │
│                    │   resource processor:   │                           │
│                    │   确保 deployment.environment 存在   │                           │
│                    └───────────┬─────────────┘                           │
│                                │ OTLP gRPC                               │
│                                ▼                                         │
│                    ┌─────────────────────────┐                           │
│                    │   Tempo (本 Skill)      │                           │
│                    │   tempo-{env}.renew.com │                           │
│                    │   :14317                │                           │
│                    │                         │                           │
│                    │   原生保留 resource      │                           │
│                    │   attributes            │                           │
│                    └─────────────────────────┘                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Tempo 在两种方案中的统一职责

| 职责 | 说明 |
|------|------|
| **协议统一** | 两种方案最终都通过 OTLP 协议（gRPC/HTTP）推送 traces |
| **入口统一** | 都通过 OTel Collector → Tempo 链路 |
| **环境标识** | 都通过 `deployment.environment` resource attribute 区分环境 |
| **查询统一** | Grafana 通过 TraceQL `{resource.deployment.environment="fat"}` 统一查询 |

### setup-tempo 提供的核心能力

| 配置项 | 值 | 作用 |
|--------|-----|------|
| OTLP gRPC 端口 | `14317:4317` | 接收 OTel Collector 转发的 traces |
| OTLP HTTP 端口 | `14318:4318` | 备用协议 |
| Resource Attributes | **无处理（原生保留）** | 保留 `deployment.environment` 环境标识 |

**关键点**：两种方案的差异在应用层和 OTel Collector 层处理，Tempo 只需做"被动接收者"，接收标准 OTLP 格式数据并原生保留所有 resource attributes。

---

## Spring Boot 3.x 集成

### Micrometer Tracing + OpenTelemetry Bridge

1. 添加 Maven 依赖：

```xml
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-tracing-bridge-otel</artifactId>
</dependency>
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-otlp</artifactId>
</dependency>
```

2. `application.yml` 配置：

```yaml
management:
  tracing:
    sampling:
      probability: 1.0  # 生产环境建议 0.1 (10%)

otel:
  exporter:
    otlp:
      endpoint: http://otel-{env}.renew.com:4318
      protocol: http/protobuf
```

3. 验证：启动应用后调用任意接口，在 Grafana Tempo 数据源中通过 TraceQL 查询 Trace。

### Spring Boot 2.x + OpenTelemetry Agent（替代方案）

对于 Spring Boot 2.x 项目，可使用 OpenTelemetry Java Agent。Agent jar 由 `setup-gitlab-runner` 统一管理（宿主机 `/opt/tech-stack/cicd/opentelemetry-javaagent.jar`），通过 K8s volumes 挂载到 Pod 容器内 `/opt/otel/`：

```bash
java -javaagent:/opt/otel/opentelemetry-javaagent.jar \
     -Dotel.service.name=my-service \
     -Dotel.exporter.otlp.endpoint=http://otel-{env}.renew.com:4318 \
     -Dotel.exporter.otlp.protocol=http/protobuf \
     -jar my-app.jar
```

## Grafana 集成

### 添加 Tempo 数据源

1. Grafana -> Configuration -> Data Sources -> Add data source
2. 选择 **Tempo**
3. URL 填写：`http://tempo-{env}.renew.com:3200`（如 `tempo-nonprod.renew.com:3200`）
4. 保存并测试

### TraceQL 查询示例

```
# 查找指定服务的所有 Trace
{ resource.service.name = "my-service" }

# 查找耗时超过 500ms 的 Span
{ duration > 500ms }

# 查找包含错误的 Trace
{ status = error }

# 组合查询
{ resource.service.name = "my-service" && duration > 1s && status = error }
```

### 环境隔离查询

Tempo 原生保留 OTLP resource attributes，包括 `deployment.environment`。该属性由 OTel Collector 的 resource processor 注入（见 `setup-otel-collector`），Tempo 无需额外配置即可按环境过滤 traces。

```
# 查询 FAT 环境的所有 traces
{ resource.deployment.environment = "fat" }

# 查询 FAT 环境中指定服务的错误 traces
{ resource.deployment.environment = "fat" && resource.service.name = "loan-service" && status = error }

# 对比多个环境
{ resource.deployment.environment =~ "fat|uat" }
```

**环境标识注入链路**：
```
Spring Boot Pod
    │  OTEL_RESOURCE_ATTRIBUTES=deployment.environment={env}
    ▼
OTel Collector (resource processor)
    │  action: insert（确保属性存在）
    ▼
Tempo
    │  原生保留，无需配置
    ▼
Grafana TraceQL 查询
```

## Metrics Generation（指标生成）

Tempo 可以从 Trace 数据自动生成以下指标，通过 `remote_write` 发送到 Prometheus：

- **service-graphs**: 服务间调用关系图指标（请求量、延迟、错误率）
- **span-metrics**: 按 Span 名称聚合的指标（请求量、延迟分布）

前提条件：
1. setup-prometheus 已部署（地址由 `.env` 中 `PROMETHEUS_HOST`:`PROMETHEUS_PORT` 配置）
2. Prometheus 已开启 `remote-write-receiver` 功能

在 Grafana 中导入 Service Graph 视图即可查看服务拓扑。

## 数据备份与恢复

### 备份

Tempo 数据存储在工作目录的 `data/tempo/` 下，包含：

- `wal/` — Write-Ahead Log，正在写入的 Trace 数据
- `blocks/` — 已压实的 Trace 数据块
- `generator/wal/` — metrics_generator 的 WAL 数据

```bash
# 本地备份（建议在低峰期执行）
tar -czf tempo-backup-$(date +%Y%m%d).tar.gz -C /opt/tech-stack/tempo-{env}/data/tempo .

# 远程备份
ssh <USER>@<HOST> "tar -czf /tmp/tempo-backup-\$(date +%Y%m%d).tar.gz -C /opt/tech-stack/tempo-{env}/data/tempo ."
```

### 恢复

```bash
# 1. 停止 Tempo
cd /opt/tech-stack/tempo-{env} && docker compose down

# 2. 清除现有数据并解压备份
rm -rf data/tempo/*
tar -xzf tempo-backup-YYYYMMDD.tar.gz -C data/tempo/

# 3. 修复权限并重新启动
chown -R 10001:10001 data/tempo 2>/dev/null || chmod -R 777 data/tempo
docker compose up -d
```

### 保留策略

默认保留 7 天（`TEMPO_RETENTION=168h`）。修改 `.env` 中的 `TEMPO_RETENTION` 值后，重新运行 `/setup-tempo start` 即可生效（会重新渲染配置）。

## 生产注意事项

1. **Tempo HTTP API 无认证保护**：端口 3200 默认无认证，生产环境应通过防火墙限制访问来源，仅允许 Grafana 和运维网段访问
2. **OTLP 端点无 TLS**：Tempo 的 OTLP 接收端点未启用 TLS，但在标准架构中 Tempo 仅接收 OTel Collector 的内部转发流量（网络隔离），风险可控
3. **Prometheus remote_write 无认证**：metrics_generator 向 Prometheus 推送指标时无认证，确保 Prometheus 与 Tempo 在同一可信网络内
4. **数据目录权限**：Tempo 容器以 UID 10001 运行，数据目录需确保该用户可写；`start` 流程已自动处理权限
5. **资源限制**：生产环境根据 Trace 流量调整 `TEMPO_MEMORY_LIMIT`，建议 2g 起步，高流量场景增加至 4g-8g
6. **数据保留与磁盘**：默认保留 7 天，请根据磁盘容量和合规要求调整 `TEMPO_RETENTION`；建议监控 `data/tempo/` 目录大小
7. **定期备份**：对于重要环境，建议每日备份 `data/tempo/blocks/` 目录（WAL 数据可不备份，重启后会重建）
