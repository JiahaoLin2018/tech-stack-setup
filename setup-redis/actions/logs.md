# Action: logs

查看 Redis 容器日志（支持本地和远程两种部署模式）。

## 命令格式

```
/setup-redis logs [--env <env>] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]
```

## 步骤

1. **解析 --env 参数**（默认 `dev`，合法值 `dev|sit|fat|uat|prod`，传错报错退出）：
   - `DEPLOY_DIR=/opt/tech-stack/redis-${ENV}`
   - `CONTAINER=tech-redis-${ENV}`

2. **查看最近 50 行日志**：
   ```bash
   ssh ... "docker logs ${CONTAINER} --tail 50 2>&1"
   ```

3. **如需实时跟踪日志**，提示用户手动执行：
   ```bash
   ssh $USER@$HOST "docker logs ${CONTAINER} -f"
   ```

4. **查看慢查询日志**（最近 10 条）：
   ```bash
   ssh ... "source ${DEPLOY_DIR}/.env 2>/dev/null && \
     docker exec ${CONTAINER} redis-cli -a \"\${REDIS_PASSWORD}\" slowlog get 10 2>/dev/null || echo '无慢查询记录'"
   ```
