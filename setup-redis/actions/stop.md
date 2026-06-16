# Action: stop

停止 Redis 服务（支持本地和远程两种部署模式）。

## 命令格式

```
/setup-redis stop [--env <env>] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]
```

## 步骤

1. **解析 --env 参数**（默认 `dev`，合法值 `dev|sit|fat|uat|prod`，传错报错退出）：
   - `DEPLOY_DIR=/opt/tech-stack/redis-${ENV}`
   - `CONTAINER=tech-redis-${ENV}`

2. **远程停止**：
   ```bash
   ssh ... "cd ${DEPLOY_DIR} && docker compose stop"
   ```

3. **确认结果**：
   ```bash
   ssh ... "docker inspect ${CONTAINER} > /dev/null 2>&1 && echo '⚠️  容器仍存在' || echo '✅ Redis 容器已停止'"
   ```

4. **数据保留提示**：
   ```
   📁 远程 AOF 持久化文件保留在 ${DEPLOY_DIR}/data，重新 start 后数据可自动恢复。
   ```
