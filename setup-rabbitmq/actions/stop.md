# Action: stop

停止 RabbitMQ 服务（支持本地和远程两种部署模式）。

## 命令格式

```
/setup-rabbitmq stop [--env <env>] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]
```

## 步骤

1. **解析 --env 参数**（默认 `dev`，合法值 `dev|sit|fat|uat|prod`，传错报错退出）：
   - `DEPLOY_DIR=/opt/tech-stack/rabbitmq-${ENV}`
   - `CONTAINER=tech-rabbitmq-${ENV}`

2. **优雅停止**：
   ```bash
   ssh ... "docker exec ${CONTAINER} rabbitmqctl stop_app 2>/dev/null || true"
   ```

3. **远程停止**：
   ```bash
   ssh ... "cd ${DEPLOY_DIR} && docker compose stop"
   ```

4. **确认结果**：
   ```bash
   ssh ... "docker inspect ${CONTAINER} > /dev/null 2>&1 && echo '⚠️  容器仍存在' || echo '✅ RabbitMQ 容器已停止'"
   ```

5. **数据保留提示**：
   ```
   📁 远程队列和消息数据保留在 ${DEPLOY_DIR}/data，重新 start 后自动恢复。
   ```
