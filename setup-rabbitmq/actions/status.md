# Action: status

查看 RabbitMQ 容器运行状态（支持本地和远程两种部署模式）。

## 命令格式

```
/setup-rabbitmq status [--env <env>] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]
```

## 步骤

1. **解析 --env 参数**（默认 `dev`，合法值 `dev|sit|fat|uat|prod`，传错报错退出）：
   - `CONTAINER=tech-rabbitmq-${ENV}`

2. **查看容器状态**：
   ```bash
   ssh ... "docker inspect ${CONTAINER} --format='状态: {{.State.Status}}  健康: {{.State.Health.Status}}' 2>/dev/null || echo '容器未运行'"
   ```

3. **查看资源占用**：
   ```bash
   ssh ... "docker stats ${CONTAINER} --no-stream --format 'CPU: {{.CPUPerc}}  内存: {{.MemUsage}}' 2>/dev/null"
   ```

4. **查看节点状态**：
   ```bash
   ssh ... "docker exec ${CONTAINER} rabbitmqctl status 2>/dev/null | grep -E 'RabbitMQ|Uptime|Memory|Disk'"
   ```

5. **查看队列列表**：
   ```bash
   ssh ... "docker exec ${CONTAINER} rabbitmqctl list_queues name messages consumers 2>/dev/null"
   ```
