# action: stop — 停止 Tempo

## 参数解析

> 继承主调用的 `--env` 参数，`ENV` = nonprod 或 prod。

## 步骤

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  cd /opt/tech-stack/tempo-${ENV}
  docker compose stop
"
```

输出：`远程 Tempo（${ENV}）已停止（数据目录 /opt/tech-stack/tempo-${ENV}/data/ 已保留）`

---

## 说明

- `docker compose stop` 仅停止容器，不删除容器，不删除数据目录
- 如需彻底清除 Trace 数据：`rm -rf /opt/tech-stack/tempo-${ENV}/data/tempo/`
- Tempo 不支持热重载配置，修改 `.env` 后重新执行 `/setup-tempo start --env ${ENV}` 即可（会重新渲染模板并重启容器）

---

## 恢复服务

```bash
cd /opt/tech-stack/tempo-${ENV} && docker compose start
```
