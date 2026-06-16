# action: stop — 停止 Consul

## `--env` 参数处理

```bash
case "${ENV:-dev}" in
  dev|sit|fat|uat|prod) ;;
  *) echo "ERROR: --env 参数无效 '${ENV}'，合法值：dev|sit|fat|uat|prod" && exit 1 ;;
esac
DEPLOY_DIR="/opt/tech-stack/consul-${ENV:-dev}"
CONTAINER_NAME="tech-consul-${ENV:-dev}"
```

## 步骤

```bash
SSH_CMD "cd ${DEPLOY_DIR} && docker compose stop"
```

执行后确认容器已停止：

```bash
SSH_CMD "docker ps --filter name=${CONTAINER_NAME}"
```

无输出行表示容器已成功停止。

---

## 恢复服务

```bash
SSH_CMD "cd ${DEPLOY_DIR} && docker compose start"
```
