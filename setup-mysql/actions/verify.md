# Action: verify

验证 MySQL 服务可连接性（支持本地和远程两种部署模式）。

## 命令格式

```
/setup-mysql verify [--env <env>] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]
```

## 步骤

1. **解析 --env 参数**（默认 `dev`，合法值 `dev|sit|fat|uat|prod`，传错报错退出）：
   - `DEPLOY_DIR=/opt/tech-stack/mysql-${ENV}`
   - `CONTAINER=tech-mysql-${ENV}`

2. **验证 root 连接**：
   ```bash
   ssh ... "source ${DEPLOY_DIR}/.env && \
     docker exec ${CONTAINER} mysqladmin ping -h localhost -p\"\${MYSQL_ROOT_PASSWORD}\" --silent \
     && echo '✅ root 连接正常' || echo '❌ root 连接失败'"
   ```

3. **验证应用用户连接**：
   ```bash
   ssh ... "source ${DEPLOY_DIR}/.env && \
     docker exec ${CONTAINER} mysql -u \"\${MYSQL_APP_USER:-appuser}\" -p\"\${MYSQL_APP_PASSWORD}\" \
     -e \"SELECT 'app user OK' AS result;\" \"\${MYSQL_DATABASE:-appdb}\" 2>/dev/null \
     && echo '✅ 应用用户连接正常' || echo '❌ 应用用户连接失败'"
   ```

4. **域名连接测试**（需本地安装 mysql client）：
   ```bash
   mysql -h mysql-${ENV}.renew.com -P ${MYSQL_PORT:-3306} -u root -p -e "SELECT VERSION();" 2>/dev/null \
     && echo "✅ 域名连接可达：mysql-${ENV}.renew.com" || echo "❌ 连接失败，检查 DNS hosts.lan 配置和防火墙端口"
   ```
