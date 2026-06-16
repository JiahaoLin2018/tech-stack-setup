# setup-prometheus — Prometheus + Alertmanager 指标监控与告警部署工具

使用 Docker Compose 部署 Prometheus v3.2.0 + Alertmanager v0.28.0 指标监控与告警体系，支持 Spring Boot Actuator 指标接入和 Consul 服务自动发现，支持本地和远程两种部署模式。

> **可视化面板**：Grafana 已独立为 `setup-grafana` skill，预配置 Prometheus 数据源，部署后即可查看指标 Dashboard。

## B 类 --env 契约

本 Skill 支持 `--env nonprod|prod` 参数，部署两套独立实例：

| 环境 | 说明 | 部署目录 | 容器名 | 域名 |
|------|------|---------|--------|------|
| `nonprod` | 非生产共用（采集 dev/sit/fat/uat 四套） | `/opt/tech-stack/prometheus-nonprod/` | `tech-prometheus-nonprod` | `prometheus-nonprod.renew.com` |
| `prod` | 生产独立（仅采集 prod 一套） | `/opt/tech-stack/prometheus-prod/` | `tech-prometheus-prod` | `prometheus-prod.renew.com` |

**配置模板切换**：nonprod 使用 `prometheus.nonprod.yml`（4 套 consul_sd + 4 套 exporter），prod 使用 `prometheus.prod.yml`（单 prod 环境）。

## 安装

```bash
bash setup-prometheus/install.sh
```

脚本将 `setup-prometheus/` 全部内容复制到 `~/.claude/skills/setup-prometheus/`。

## 目录结构

```
setup-prometheus/
├── SKILL.md                                  # 路由指令（Claude 读取）
├── actions/
│   ├── start.md                              # 启动流程（本地 + 远程）
│   ├── stop.md                               # 停止服务
│   ├── status.md                             # 运行状态
│   ├── verify.md                             # 服务验证
│   └── logs.md                               # 日志查看与排查
├── references/
│   ├── docker-compose.yml                    # 生产级 Compose 配置
│   ├── .env.example                          # 环境变量模板
│   └── conf/
│       ├── prometheus/
│       │   ├── prometheus.nonprod.yml        # 非生产抓取配置（4 套 consul_sd：dev/sit/fat/uat）
│       │   ├── prometheus.prod.yml           # 生产抓取配置（1 套 consul_sd：prod）
│       │   └── rules/
│       │       └── infra-alerts.yml          # 预置告警规则（Spring Boot + 中间件）
│       └── alertmanager/
│           └── alertmanager.yml              # Alertmanager 路由和接收器配置
├── README.md
└── install.sh
```

## 快速使用

```
/setup-prometheus                               # 本地启动（默认 start）
/setup-prometheus start                         # 本地启动
/setup-prometheus stop                          # 本地停止
/setup-prometheus status                        # 查看状态
/setup-prometheus verify                        # 验证服务
/setup-prometheus logs                          # 查看日志

# 远程部署（密码认证）
/setup-prometheus start --host <HOST> --user ubuntu --password mypass

# 远程部署（密钥认证）
/setup-prometheus start --host <HOST> --user ubuntu --key ~/.ssh/id_rsa
```

## 服务端口

| 服务 | 端口 | 说明 |
|------|------|------|
| Prometheus | 9090 | 指标采集与存储、PromQL 查询 |
| Alertmanager | 9093 | 告警聚合与通知路由 |

## 工作目录

- **nonprod**：`/opt/tech-stack/prometheus-nonprod/`
- **prod**：`/opt/tech-stack/prometheus-prod/`

首次 `start` 时自动从 `references/` 复制配置模板（含告警规则）到工作目录，**不会覆盖已有配置**。

## 环境变量（.env）

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `ENV` | `nonprod` | 部署环境（nonprod/prod） |
| `PROMETHEUS_RETENTION` | `30d` | 指标数据保留时长 |
| `PROMETHEUS_PORT` | `9090` | Prometheus 对外端口 |
| `ALERTMANAGER_PORT` | `9093` | Alertmanager 对外端口 |

> **说明**：采集目标地址在 `prometheus.nonprod.yml` / `prometheus.prod.yml` 中硬编码，通过模板切换实现环境隔离，无需额外环境变量。

## 采集目标

### 基础设施指标（内置，无需额外 exporter）

| 服务 | 采集地址 | 指标内容 |
|------|---------|---------|
| RabbitMQ | `rabbitmq-{env}.renew.com:15692/metrics` | 队列深度、连接数、消息速率、内存/磁盘 |
| OTel Collector | `otel-{env}.renew.com:8888/metrics` | 接收/导出吞吐量、处理延迟、错误率 |
| Loki | `loki-{env}.renew.com:3100/metrics` | 请求延迟、ingester 状态、chunk 编码 |
| Tempo | `tempo-{env}.renew.com:3200/metrics` | Ingester 状态、查询延迟、span 接收量 |

### 数据库指标（exporter sidecar，已集成在各 setup-* skill 中）

| 服务 | Exporter | 采集地址 | 指标内容 |
|------|----------|---------|---------|
| MySQL | mysqld_exporter v0.16.0 | `mysql-{env}.renew.com:9104/metrics` | 连接数、慢查询、InnoDB 缓冲池、QPS |
| Redis | redis_exporter v1.67.0 | `redis-{env}.renew.com:9121/metrics` | 内存使用率、命中率、Key 驱逐、连接数 |
| MongoDB | mongodb_exporter 0.43.1 | `mongodb-{env}.renew.com:9216/metrics` | 连接数、WiredTiger 缓存、操作计数 |

Exporter 随数据库容器自动启动（`depends_on: service_healthy`），无需手动部署。

告警规则中已预置 MySQL/Redis/RabbitMQ 告警模板，部署对应 exporter 后自动生效。

### Spring Boot 微服务

通过 Consul 服务发现自动采集带 `metrics` tag 的服务，无需手动配置。

## Spring Boot 接入

### 两种 OTel 接入方案

本项目支持两种 Spring Boot OTel 接入方案（详见 `observability-env-isolation.md`）：

| 方案 | 适用版本 | 说明 |
|------|---------|------|
| **A. Micrometer + OTel Bridge** | Spring Boot 3.x（主力） | 云原生标准，指标零冲突，代码可治理 |
| **B. OTel Java Agent** | Spring Boot 2.x（兜底） | 字节码注入，无感接入，老系统兼容 |

### Prometheus 对两种方案的透明支持

两种方案在 Metrics 采集层面**完全相同**，Prometheus 配置无需区分：

```
方案 A (SB 3.x)                    方案 B (SB 2.x)
┌───────────────────┐             ┌───────────────────┐
│ Micrometer        │             │ Micrometer        │
│ Prometheus        │             │ Prometheus        │
│ Registry          │             │ Registry          │
│       │           │             │       │           │
│       ▼           │             │       ▼           │
│ /actuator/        │             │ /actuator/        │
│   prometheus      │             │   prometheus      │
└─────────┬─────────┘             └─────────┬─────────┘
          │                                 │
          └────────────┬────────────────────┘
                       │
                       ▼
              ┌─────────────────┐
              │ Prometheus      │  ← consul_sd + tags: metrics
              │ (拉取)          │  ← relabel 附加 env 标签
              └─────────────────┘
```

> **关键点**：两种方案的差异在于 Traces/Logs 走 OTLP 推送到 OTel Collector，与 Prometheus 无关。Prometheus 只负责拉取 `/actuator/prometheus` 端点。

### 接入步骤

#### 1. 注册 Consul 时打 `metrics` 标签（必须）

```yaml
# application.yml（方案 A/B 都需要）
spring:
  cloud:
    consul:
      host: consul-${spring.profiles.active}.renew.com
      port: 8500
      discovery:
        tags: metrics              # 必须：Prometheus consul_sd 通过此标签发现服务
        health-check-interval: 10s
```

#### 2. 添加依赖

```xml
<!-- 方案 A/B 都需要 -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

#### 3. 暴露 Prometheus 端点

```yaml
# application.yml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  prometheus:
    metrics:
      export:
        enabled: true
```

#### 4. 方案 B 额外配置（仅 Agent 模式）

若使用方案 B（Java Agent），需关闭 Agent 指标导出，避免与 Actuator 冲突：

```yaml
# app.sh 生成的环境变量（方案 B）
env:
  - name: OTEL_METRICS_EXPORTER
    value: "none"           # 关闭 Agent 指标导出
  - name: OTEL_INSTRUMENTATION_MICROMETER_ENABLED
    value: "false"          # 关闭 Agent 的 Micrometer Bridge
```

### 验证

```bash
# 检查 Actuator 端点
curl http://<pod-ip>:<port>/actuator/prometheus

# Prometheus 自动发现后，可通过以下查询验证
# http://prometheus-{env}-ui.renew.com
# 查询：up{env="fat"}
```

### 详细文档

完整的 OTel 接入指南（含 Traces/Logs 配置）见：
- `observability-env-isolation.md`：LGT 栈 env 标签逻辑隔离实现
- `setup-cicd/actions/integrate.md`：业务服务接入基础设施完整示例

## 跨机 Consul 配置

Consul 地址在 `prometheus.nonprod.yml` / `prometheus.prod.yml` 中硬编码。`actions/start.md` 上传时按 `--env` 选择对应模板，远程目标统一命名为 `prometheus.yml`：

| 本地源文件 | 远程目标路径 |
|---|---|
| `references/conf/prometheus/prometheus.nonprod.yml` | `/opt/tech-stack/prometheus-nonprod/conf/prometheus/prometheus.yml` |
| `references/conf/prometheus/prometheus.prod.yml` | `/opt/tech-stack/prometheus-prod/conf/prometheus/prometheus.yml` |

跨机修改步骤：

```bash
# 编辑对应环境的远程配置文件
vim /opt/tech-stack/prometheus-{env}/conf/prometheus/prometheus.yml
# 修改 consul_sd_configs 中的 server 地址

# 热重载配置
curl -X POST http://localhost:9090/-/reload
```

## 告警配置

编辑 `conf/alertmanager/alertmanager.yml` 配置通知渠道（钉钉/邮件/Webhook），告警规则放入 `conf/prometheus/rules/` 目录（.yml 格式），修改后热重载生效。

## 可视化面板

Grafana 已独立为 [`setup-grafana`](../setup-grafana/) skill，预配置了 Prometheus、Tempo、Loki 三个数据源。部署 Grafana 后可直接使用推荐 Dashboard：

| Dashboard | ID | 说明 |
|-----------|-----|------|
| JVM (Micrometer) | 4701 | JVM 核心指标 |
| Spring Boot 统计 | 12900 | HTTP 请求与性能 |
| MySQL Overview | 7362 | MySQL 性能监控 |
| Redis Dashboard | 11835 | Redis 运行状态 |
