# action: verify — 验证 OpenTelemetry Collector 服务

## 参数解析

> 继承主调用的 `--env` 参数，`ENV` = nonprod 或 prod。

## 步骤

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  echo '=== 验证 OTel Collector 健康状态 ==='
  curl -sf http://localhost:8888/metrics > /dev/null 2>&1 \
    && echo 'OTel Collector 健康检查正常' \
    || echo 'OTel Collector 未就绪'

  echo ''
  echo '=== 验证 Collector 自身指标 ==='
  curl -sf http://localhost:8888/metrics | head -20 2>/dev/null \
    && echo 'Collector Metrics 端点正常' \
    || echo 'Collector Metrics 端点未就绪'

  echo ''
  echo '=== 验证 OTLP gRPC 端口 (4317) ==='
  (echo > /dev/tcp/localhost/4317) 2>/dev/null \
    && echo 'OTLP gRPC 端口 4317 可达' \
    || echo 'OTLP gRPC 端口 4317 不可达'

  echo ''
  echo '=== 验证 OTLP HTTP 端口 (4318) ==='
  curl -sf -o /dev/null -w '%{http_code}' http://localhost:4318/v1/traces 2>/dev/null
  echo ''
  echo 'OTLP HTTP 端口 4318 连通性已测试'
"
```

---

## 访问地址汇总

| 端口 | 地址 | 说明 |
|------|------|------|
| 4317 | \<HOST\>:4317 | OTLP gRPC 接收端（应用发送 Traces/Logs） |
| 4318 | http://\<HOST\>:4318 | OTLP HTTP 接收端（应用发送 Traces/Logs） |
| 8888 | http://\<HOST\>:8888/metrics | Collector 自身运行指标（兼健康检查） |
