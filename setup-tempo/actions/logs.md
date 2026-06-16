# action: logs — 查看 Tempo 容器日志

## 参数解析

> 继承主调用的 `--env` 参数，`ENV` = nonprod 或 prod。

## 步骤

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "docker logs tech-tempo-${ENV} --tail 100 -f"
```

---

## 常见错误排查

| 错误关键词 | 含义 | 解决方法 |
|-----------|------|---------|
| `failed to create block` | 数据目录权限问题 | `chown -R 10001:10001 /opt/tech-stack/tempo-${ENV}/data/tempo`（或 `chmod -R 777` 作为备选） |
| `connection refused` (metrics_generator remote_write) | Prometheus 不可达 | 检查 Prometheus 是否运行；修改 `.env` 中 `PROMETHEUS_HOST` 后重新 `/setup-tempo start --env ${ENV}` |
| `error loading config` | tempo-config.yml 语法错误 | 检查 `.env` 变量是否完整，重新执行 `/setup-tempo start --env ${ENV}` 渲染模板 |
| `port already in use` | 端口被占用 | 修改 `.env` 中对应端口号，或停止占用端口的进程 |
| `failed to listen on 0.0.0.0:4317` | gRPC 端口冲突 | 检查是否有其他 OTLP collector 占用 4317 端口 |
| `wal replay` 相关 | WAL 文件损坏 | 清除 WAL 目录：`rm -rf /opt/tech-stack/tempo-${ENV}/data/tempo/wal/*` 后重启 |

## 查看指定时间范围的日志

```bash
# 最近 30 分钟
docker logs tech-tempo-${ENV} --since 30m

# 指定时间之后
docker logs tech-tempo-${ENV} --since "2024-01-01T00:00:00"
```
