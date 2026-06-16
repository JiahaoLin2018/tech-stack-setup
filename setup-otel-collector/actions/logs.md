# action: logs — 查看 OpenTelemetry Collector 容器日志

## 参数解析

> 继承主调用的 `--env` 参数，`ENV` = nonprod 或 prod。

## 步骤

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "docker logs tech-otel-collector-${ENV} --tail 100 -f"
```

---

## 常见错误排查

| 错误关键词 | 含义 | 解决方法 |
|-----------|------|---------|
| `connection refused` (tempo/loki) | 后端服务不可达 | 检查 `.env` 中的 `TEMPO_HOST`、`LOKI_HOST` 是否正确；确认后端服务已启动 |
| `bind: address already in use` (4317/4318) | 端口冲突，可能 Tempo 也暴露了 4317/4318 | 修改 `.env` 中的 `OTEL_GRPC_PORT` / `OTEL_HTTP_PORT`，或停止占用端口的服务（如 Tempo 直接暴露模式） |
| `memory limit exceeded` | 内存超限 | 增大 `.env` 中的 `OTEL_MEMORY_LIMIT`，同步增大 `otel-collector-config.yml` 中 `memory_limiter.limit_mib` |
| `failed to export` / `exporting failed` | 后端拒绝接收数据 | 检查后端是否开启了对应的写入接口（如 Prometheus 需开启 `--web.enable-remote-write-receiver`） |
| `dropping data` / `queue is full` | 数据积压超过队列容量 | 检查后端服务性能，或在 exporter 中配置 `sending_queue` 增大队列 |
| `dial tcp: lookup tempo` / `no such host` | DNS 解析失败 | 确认 DNS 配置正确（setup-dns configure），域名 `tempo-{env}.renew.com` 可解析 |
| `TLS handshake error` | TLS 配置问题 | 确认 exporter 的 `tls.insecure: true` 配置（内网通信不需要 TLS） |

## 查看特定级别日志

```bash
# 仅查看错误日志
docker logs tech-otel-collector-${ENV} 2>&1 | grep -i "error"

# 仅查看警告日志
docker logs tech-otel-collector-${ENV} 2>&1 | grep -i "warn"
```

## 动态调整日志级别

修改 `otel-collector-config.yml` 中的 `service.telemetry.logs.level` 为 `debug`，然后重启：

```bash
cd /opt/tech-stack/otel-collector-${ENV}
docker compose restart
```
