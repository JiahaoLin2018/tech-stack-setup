# action: stop — 停止 OpenTelemetry Collector

## 参数解析

> 继承主调用的 `--env` 参数，`ENV` = nonprod 或 prod。

## 步骤

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  cd /opt/tech-stack/otel-collector-${ENV}
  docker compose stop
"
```

输出：`远程 OpenTelemetry Collector（${ENV}）已停止（配置目录 /opt/tech-stack/otel-collector-${ENV}/ 已保留）`

---

## 说明

- `docker compose stop` 仅停止容器，不删除容器，不删除配置目录
- OTel Collector 是无状态服务，无数据目录需要清理
- 如需彻底清除配置：`rm -rf /opt/tech-stack/otel-collector-${ENV}/`
- 停止 OTel Collector 后，应用发送到 4317/4318 的数据将被丢弃，请确保应用端有重试机制或先停止应用

---

## 恢复服务

```bash
cd /opt/tech-stack/otel-collector-${ENV} && docker compose start
```
