# Action: verify

验证 RabbitMQ 服务可用性（支持本地和远程两种部署模式）。

## 命令格式

```
/setup-rabbitmq verify [--env <env>] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]
```

## 步骤

1. **解析 --env 参数**（默认 `dev`，合法值 `dev|sit|fat|uat|prod`，传错报错退出）：
   - `DEPLOY_DIR=/opt/tech-stack/rabbitmq-${ENV}`
   - `CONTAINER=tech-rabbitmq-${ENV}`

2. **验证节点 ping**：
   ```bash
   ssh ... "docker exec ${CONTAINER} rabbitmq-diagnostics -q ping 2>/dev/null \
     && echo '✅ RabbitMQ 节点响应正常' || echo '❌ RabbitMQ 节点无响应'"
   ```

3. **验证管理员账号**：
   ```bash
   ssh ... "source ${DEPLOY_DIR}/.env && \
     docker exec ${CONTAINER} rabbitmqctl authenticate_user \"\${RABBITMQ_USER:-admin}\" \"\${RABBITMQ_PASSWORD}\" 2>/dev/null \
     && echo '✅ 管理员账号认证通过' || echo '❌ 管理员账号认证失败'"
   ```

4. **验证 Management UI 可达性**（域名方式，通过 infra-nginx 反代）：
   ```bash
   curl -s -o /dev/null -w "%{http_code}" \
     -u "<username>:<password>" \
     "http://rabbitmq-${ENV}-ui.renew.com/api/overview" 2>/dev/null \
     | grep -q "200" && echo "✅ Management API 可达：rabbitmq-${ENV}-ui.renew.com" || echo "❌ Management API 不可达，请检查 infra-nginx 配置"
   ```

5. **验证 Prometheus 指标端点**（直连方式，Prometheus 直连采集）：
   ```bash
   curl -s -o /dev/null -w "%{http_code}" \
     "http://rabbitmq-${ENV}.renew.com:${RABBITMQ_PROMETHEUS_PORT:-15692}/metrics" 2>/dev/null \
     | grep -q "200" && echo "✅ Prometheus 指标端点可达：rabbitmq-${ENV}.renew.com:15692" || echo "❌ 指标端点不可达，检查 DNS hosts.lan 和防火墙端口"
   ```
