# action: status — 查看 Loki 运行状态

## 参数解析

> 继承主调用的 `--env` 参数，`ENV` = nonprod 或 prod。

## 步骤

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "docker ps \
    --filter 'name=tech-loki-${ENV}' \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
```

---

## 补充：查看资源占用

```bash
docker stats \
  tech-loki-${ENV} \
  --no-stream \
  --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
```

## 补充：查看 Loki 摄入状态

访问 http://localhost:3100/metrics 可查看摄入速率、chunk 大小等运行指标。

关键指标：
- `loki_ingester_streams_created_total` — 创建的日志流总数
- `loki_distributor_bytes_received_total` — 接收的字节总量
- `loki_ingester_chunk_stored_total` — 存储的 chunk 总数
