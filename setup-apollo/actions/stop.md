# action: stop — 停止 Apollo

## `--env` 参数处理

```bash
case "${ENV:-nonprod}" in
  nonprod|prod) ;;
  *) echo "ERROR: --env 参数无效 '${ENV}'，合法值：nonprod|prod" && exit 1 ;;
esac
DEPLOY_DIR="/opt/tech-stack/apollo-${ENV:-nonprod}"
```

## 步骤

```bash
SSH_CMD "cd ${DEPLOY_DIR} && docker compose stop"
```

执行后确认 Apollo 容器已停止：

```bash
SSH_CMD "docker ps --filter name=tech-apollo --format 'table {{.Names}}\t{{.Status}}'"
```

容器状态应为 Exited（已停止但容器保留），可通过 `docker compose start` 恢复。

> 注意：停止后 MySQL 数据仍持久化在数据目录中，重新 start 后数据恢复正常。

---

## 恢复服务

```bash
SSH_CMD "cd ${DEPLOY_DIR} && docker compose start"
```
