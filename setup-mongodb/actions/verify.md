# Action: verify

验证 MongoDB 服务可连接性（支持本地和远程两种部署模式）。

## 命令格式

```
/setup-mongodb verify [--env <env>] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]
```

## 步骤

1. **解析 --env 参数**（默认 `dev`，合法值 `dev|sit|fat|uat|prod`，传错报错退出）：
   - `DEPLOY_DIR=/opt/tech-stack/mongodb-${ENV}`
   - `CONTAINER=tech-mongodb-${ENV}`

2. **验证管理员连接**：
   ```bash
   ssh ... "source ${DEPLOY_DIR}/.env && \
     docker exec ${CONTAINER} mongosh --quiet \
     -u \"\${MONGO_INITDB_ROOT_USERNAME}\" -p \"\${MONGO_INITDB_ROOT_PASSWORD}\" \
     --authenticationDatabase admin \
     --eval 'db.runCommand({ping:1})' \
     && echo '✅ 管理员连接正常' || echo '❌ 管理员连接失败'"
   ```

3. **验证应用用户连接**：
   ```bash
   ssh ... "source ${DEPLOY_DIR}/.env && \
     docker exec ${CONTAINER} mongosh --quiet \
     -u \"\${MONGO_APP_USER}\" -p \"\${MONGO_APP_PASSWORD}\" \
     --authenticationDatabase \"\${MONGO_APP_DATABASE:-appdb}\" \
     \"\${MONGO_APP_DATABASE:-appdb}\" \
     --eval 'db.runCommand({ping:1})' \
     && echo '✅ 应用用户连接正常' || echo '❌ 应用用户连接失败'"
   ```

4. **域名连接测试**（需本地安装 mongosh）：
   ```bash
   mongosh "mongodb://<root>:<pass>@mongodb-${ENV}.renew.com:${MONGO_PORT:-27017}/admin" \
     --quiet --eval "db.runCommand({ping:1})" \
     && echo "✅ 域名连接可达：mongodb-${ENV}.renew.com" || echo "❌ 连接失败，检查 DNS hosts.lan 配置"
   ```
