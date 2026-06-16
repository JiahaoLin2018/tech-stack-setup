# action: status — 查看 OpenTelemetry Collector 运行状态

## 参数解析

> 继承主调用的 `--env` 参数，`ENV` = nonprod 或 prod。

## 步骤

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "docker ps \
    --filter 'name=tech-otel-collector-${ENV}' \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
```

---

## 补充：查看资源占用

```bash
docker stats \
  tech-otel-collector-${ENV} \
  --no-stream \
  --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
```

## 补充：查看管道状态

访问 http://localhost:8888/metrics 可查看 Collector 自身的 pipeline 处理指标，包括：
- `otelcol_receiver_accepted_spans` — 已接收的 Span 数量
- `otelcol_receiver_accepted_metric_points` — 已接收的 Metric 数据点
- `otelcol_receiver_accepted_log_records` — 已接收的 Log 记录数
- `otelcol_exporter_sent_spans` — 已发送到后端的 Span 数量
- `otelcol_exporter_send_failed_spans` — 发送失败的 Span 数量
