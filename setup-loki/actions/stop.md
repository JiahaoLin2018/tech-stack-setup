# action: stop — 停止 Loki 服务

## 参数解析

> 继承主调用的 `--env` 参数，`ENV` = nonprod 或 prod。

## 步骤

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  cd /opt/tech-stack/loki-${ENV}
  docker compose stop
"
```

输出：`远程 Loki（${ENV}）服务已停止（数据目录 /opt/tech-stack/loki-${ENV}/data/ 已保留）`

---

## 说明

- `docker compose stop` 仅停止容器，不删除容器，不删除数据目录
- 如需彻底清除 Loki 历史数据：`rm -rf /opt/tech-stack/loki-${ENV}/data/loki/`
- 如需重置配置：`rm -f /opt/tech-stack/loki-${ENV}/.env /opt/tech-stack/loki-${ENV}/docker-compose.yml`，下次 start 时会重新复制模板

---

## 恢复服务

```bash
cd /opt/tech-stack/loki-${ENV} && docker compose start
```
