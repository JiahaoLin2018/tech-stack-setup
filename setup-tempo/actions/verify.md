# action: verify — 验证 Tempo 服务

## 参数解析

> 继承主调用的 `--env` 参数，`ENV` = nonprod 或 prod。

## 步骤

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  echo '=== 验证 Tempo Ready ==='
  wget --no-verbose --tries=1 --spider http://localhost:3200/ready 2>/dev/null \
    && echo 'Tempo 正常' || echo 'Tempo 未就绪'

  echo ''
  echo '=== 验证 Tempo Status ==='
  curl -s http://localhost:3200/status | head -50

  echo ''
  echo '=== 发送测试 Trace（OTLP HTTP，远端宿主机访问 :14318） ==='
  wget -qO- --post-data='{\"resourceSpans\":[]}' \
    --header='Content-Type: application/json' \
    http://localhost:14318/v1/traces 2>/dev/null \
    && echo '测试 Trace 发送成功' || echo '测试 Trace 发送失败'

  echo ''
  echo '=== 验证 Prometheus remote_write 连通性（远端宿主机 wget） ==='
  PROM_HOST=\$(grep '^PROMETHEUS_HOST=' /opt/tech-stack/tempo-${ENV}/.env 2>/dev/null | cut -d= -f2)
  PROM_PORT=\$(grep '^PROMETHEUS_PORT=' /opt/tech-stack/tempo-${ENV}/.env 2>/dev/null | cut -d= -f2)
  PROM_HOST=\${PROM_HOST:-prometheus}
  PROM_PORT=\${PROM_PORT:-9090}
  wget --no-verbose --tries=1 --spider \
    \"http://\${PROM_HOST}:\${PROM_PORT}/api/v1/status/buildinfo\" 2>/dev/null \
    && echo \"Prometheus remote_write 端点可达（\${PROM_HOST}:\${PROM_PORT}）\" \
    || echo \"Prometheus remote_write 端点不可达（\${PROM_HOST}:\${PROM_PORT}）— metrics_generator 指标推送将失败\"
"
```

---

## 访问地址汇总

| 服务 | 地址 | 说明 |
|------|------|------|
| Tempo HTTP API | http://\<HOST\>:3200 | 健康检查、状态查询、TraceQL API |
| OTLP gRPC | \<HOST\>:14317 | OpenTelemetry gRPC 协议接收端点（OTel Collector 转发入口） |
| OTLP HTTP | http://\<HOST\>:14318 | OpenTelemetry HTTP 协议接收端点（OTel Collector 转发入口） |
| Zipkin | http://\<HOST\>:9411 | Zipkin 兼容接收端点 |
| Prometheus remote_write | http://\<PROMETHEUS_HOST\>:\<PROMETHEUS_PORT\>/api/v1/write | metrics_generator 指标推送目标 |
