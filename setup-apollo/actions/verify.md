# action: verify — 验证 Apollo

## `--env` 参数处理

```bash
case "${ENV:-nonprod}" in
  nonprod|prod) ;;
  *) echo "ERROR: --env 参数无效 '${ENV}'，合法值：nonprod|prod" && exit 1 ;;
esac
```

## 步骤

```bash
# DB 健康状态
SSH_CMD "docker inspect --format='{{.State.Health.Status}}' tech-apollo-db"

# nonprod 模式：检查各环境 Config Service
SSH_CMD "
if [ '${ENV:-nonprod}' = 'nonprod' ]; then
  for port in \${APOLLO_CONFIG_PORT_DEV:-8601} \${APOLLO_CONFIG_PORT_SIT:-8602} \${APOLLO_CONFIG_PORT_FAT:-8603} \${APOLLO_CONFIG_PORT_UAT:-8604}; do
    curl -s http://localhost:\${port}/health | grep -q '\"status\":\"UP\"' && echo \"port \${port}: UP\" || echo \"port \${port}: NOT READY\"
  done
  # Portal
  curl -s -o /dev/null -w '%{http_code}' http://localhost:\${APOLLO_PORTAL_PORT:-8070}/
  # 验证 DEV 环境 Eureka 注册情况
  curl -s http://localhost:\${APOLLO_CONFIG_PORT_DEV:-8601}/eureka/apps 2>/dev/null | grep -o '<name>[^<]*</name>'
else
  # prod 模式
  curl -s http://localhost:\${APOLLO_CONFIG_PORT_PROD:-8605}/health | grep -q '\"status\":\"UP\"' && echo 'apollo-config-prod: UP' || echo 'apollo-config-prod: NOT READY'
fi
"
```

## 故障排查

| 问题 | 可能原因 | 处理建议 |
|------|---------|---------|
| tech-apollo-db unhealthy | MySQL 初始化失败 | 执行 `/setup-apollo logs --env {env}`，查看 apollo-db 日志 |
| apollo-config-{env} 无响应 | 等待 DB 就绪中 | 等待 30 秒后重试 verify |
| apollo-admin-{env} 无响应 | 等待 config service 就绪 | 确认对应 apollo-config-{env} 已 healthy |
| apollo-portal 404 | portal 启动慢 | 等待 60 秒后重试 verify |
| Eureka 缺少 ADMINSERVICE | admin 未注册或启动中 | 等待 30 秒重试，或查看 admin 日志 |
| 所有容器无响应 | 未启动 | 执行 `/setup-apollo start --env {env}` |
