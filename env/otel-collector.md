# OTel Collector 0.120 — 部署报告

| 项目 | 值 |
|------|-----|
| 部署日期 | 2026-03-18 |
| 目标机器 | 192.168.82.93 (Server A) |
| 部署目录 | `/opt/tech-stack/otel-collector/` |
| 容器名称 | tech-otel-collector |
| 镜像 | otel/opentelemetry-collector-contrib:0.120.0 |

## 端口

| 端口 | 用途 |
|------|------|
| 4317 | OTLP gRPC（业务服务上报入口） |
| 4318 | OTLP HTTP（业务服务上报入口） |
| 8888 | 自身指标（供 Prometheus 采集） |

## 账号密码

无（OTel Collector 无认证）

## 连接方式

| 方式 | 地址 |
|------|------|
| OTLP gRPC | `otel.renew.com:4317` |
| OTLP HTTP | `http://otel.renew.com:4318` |
| Spring Boot | `-Dotel.exporter.otlp.endpoint=http://otel.renew.com:4318` |
| Metrics | http://otel.renew.com:8888/metrics |

## 数据流转

```
业务服务 → OTel Collector(:4317/:4318)
               ├── Traces  → Tempo(:14317)
               └── Logs    → Loki(:3100/otlp)

Metrics 不经过 OTel Collector，由 Prometheus 直接拉取 /actuator/prometheus
```

## 备注

- otel-collector-contrib 是最小化镜像，无 `/bin/sh`，healthcheck 使用 `[CMD, /otelcol-contrib, --version]`
