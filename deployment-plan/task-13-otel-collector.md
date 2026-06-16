# Task 13 — 部署 OTel Collector

- **状态**: ✅ 完成
- **目标机器**: 192.168.82.93
- **Skill**: setup-otel-collector
- **前置依赖**: Task 09 (Tempo), Task 10 (Loki), Task 11 (Prometheus)
- **内存预算**: 512M

## 执行内容

1. 执行 `/setup-otel-collector start` 部署 OTel Collector 0.120.0
2. 确认转发目标配置（同机，使用默认域名）
3. 验证数据转发

## .env 关键配置（同机 — 使用默认值）

```bash
TEMPO_HOST=tempo.renew.com         # Trace 转发目标
LOKI_HOST=loki.renew.com           # Log 转发目标
PROMETHEUS_HOST=prometheus.renew.com # Metrics 转发目标
```

## Skill 命令

```bash
/setup-otel-collector start --host 192.168.82.93 --user root --password foxconn.88
/setup-otel-collector verify --host 192.168.82.93 --user root --password foxconn.88
```

## 端口说明

- `:4317` — gRPC（业务服务 OTLP 上报入口）
- `:4318` — HTTP（业务服务 OTLP 上报入口）
- `:8888` — 自身指标（供 Prometheus 采集）

## 验证标准

- [ ] OTel Collector 容器运行中
- [ ] `:4317` gRPC 端口可达
- [ ] `:4318` HTTP 端口可达
- [ ] `:8888/metrics` 指标端点可访问

## 完成记录

- 开始时间:
- 完成时间:
- 备注:
