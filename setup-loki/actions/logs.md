# action: logs — 查看 Loki 容器日志

## 参数解析

> 继承主调用的 `--env` 参数，`ENV` = nonprod 或 prod。

## 步骤

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "docker logs tech-loki-${ENV} --tail 100 -f"
```

---

## 常见错误排查

| 错误关键词 | 含义 | 解决方法 |
|-----------|------|---------|
| `permission denied` | 数据目录权限问题 | `chown -R 10001:10001 /opt/tech-stack/loki-${ENV}/data/loki && chmod -R 755 /opt/tech-stack/loki-${ENV}/data/loki` |
| `failed to create block directory` | 存储目录不存在或无写权限 | 确认 `./data/loki` 挂载正确且有写权限 |
| `too many outstanding requests` | 摄入速率超限 | 调大 `.env` 中 `LOKI_INGESTION_RATE_MB` 和 `LOKI_INGESTION_BURST_SIZE_MB` |
| `max streams limit` / `per-user streams limit` | 日志流数超限 | 调大 `.env` 中 `LOKI_MAX_STREAMS_PER_USER`（默认 10000） |
| `entry out of order` | 日志时间戳乱序 | 检查日志推送端的时间戳生成逻辑，确保单个流内时间递增 |
| `context deadline exceeded` | 查询超时 | 缩小查询时间范围或调大 `query_timeout` |
| `error connecting to alertmanager` | Alertmanager 不可达 | 检查 `loki-config.yml` 中 `alertmanager_url` 配置或忽略（非必要依赖） |

## 日志级别调整

如需更详细的日志输出，修改 `.env` 中的 `LOKI_LOG_LEVEL`：

```bash
# .env
LOKI_LOG_LEVEL=debug  # 可选: debug, info, warn, error
```

修改后需重启容器：

```bash
cd /opt/tech-stack/loki-${ENV}
docker compose restart
```
