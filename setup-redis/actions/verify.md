# Action: verify

验证 Redis 服务可连接性（支持本地和远程两种部署模式）。

## 命令格式

```
/setup-redis verify [--env <env>] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]
```

## 步骤

1. **解析 --env 参数**（默认 `dev`，合法值 `dev|sit|fat|uat|prod`，传错报错退出）：
   - `DEPLOY_DIR=/opt/tech-stack/redis-${ENV}`
   - `CONTAINER=tech-redis-${ENV}`

2. **验证 PING 响应**：
   ```bash
   ssh ... "source ${DEPLOY_DIR}/.env && \
     docker exec ${CONTAINER} redis-cli -a \"\${REDIS_PASSWORD}\" ping 2>/dev/null \
     && echo '✅ Redis 连接正常（PONG）' || echo '❌ Redis 连接失败'"
   ```

3. **验证写入和读取**：
   ```bash
   ssh ... "source ${DEPLOY_DIR}/.env && \
     docker exec ${CONTAINER} redis-cli -a \"\${REDIS_PASSWORD}\" set verify_test 'ok' EX 10 2>/dev/null && \
     docker exec ${CONTAINER} redis-cli -a \"\${REDIS_PASSWORD}\" get verify_test 2>/dev/null | grep -q 'ok' \
     && echo '✅ 读写验证通过' || echo '❌ 读写验证失败'"
   ```

4. **域名连接测试**（需本地安装 redis-cli）：
   ```bash
   redis-cli -h redis-${ENV}.renew.com -p ${REDIS_PORT:-6379} -a <password> ping 2>/dev/null \
     && echo "✅ 域名连接可达：redis-${ENV}.renew.com" || echo "❌ 连接失败，检查 DNS hosts.lan 配置"
   ```
