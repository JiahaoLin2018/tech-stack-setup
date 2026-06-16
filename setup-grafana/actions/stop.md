# action: stop — 停止 Grafana

## 参数解析

> 继承主调用的 `--env` 参数，`ENV` = nonprod 或 prod。

## 步骤

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  cd /opt/tech-stack/grafana-${ENV}
  docker compose stop
"
```

输出：`远程 Grafana（${ENV}）已停止（数据目录 /opt/tech-stack/grafana-${ENV}/data/ 已保留）`

---

## 说明

- `docker compose stop` 仅停止容器，不删除容器，不删除数据目录
- 如需彻底清除 Grafana 配置和 Dashboard：`rm -rf /opt/tech-stack/grafana-${ENV}/data/grafana/`

---

## 恢复服务

```bash
cd /opt/tech-stack/grafana-${ENV} && docker compose start
```
