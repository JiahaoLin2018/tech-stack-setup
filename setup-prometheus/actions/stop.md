# action: stop — 停止 Prometheus + Alertmanager

## 参数解析

> 继承主调用的 `--env` 参数，`ENV` = nonprod 或 prod。

## 步骤

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  cd /opt/tech-stack/prometheus-${ENV}
  docker compose stop
"
```

输出：`远程 Prometheus + Alertmanager（${ENV}）已停止（数据目录 /opt/tech-stack/prometheus-${ENV}/data/ 已保留）`

---

## 说明

- `docker compose stop` 仅停止容器，不删除容器，不删除数据目录
- 如需彻底清除 Prometheus 历史数据：`rm -rf /opt/tech-stack/prometheus-${ENV}/data/prometheus/`
- Prometheus 配置热重载（无需重启）：`curl -X POST http://localhost:9090/-/reload`

---

## 恢复服务

```bash
cd /opt/tech-stack/prometheus-${ENV} && docker compose start
```
