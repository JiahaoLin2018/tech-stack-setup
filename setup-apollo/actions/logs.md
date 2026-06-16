# action: logs — 查看 Apollo 日志

## `--env` 参数处理

```bash
case "${ENV:-nonprod}" in
  nonprod|prod) ;;
  *) echo "ERROR: --env 参数无效 '${ENV}'，合法值：nonprod|prod" && exit 1 ;;
esac
```

## 步骤

```bash
# nonprod 模式：查看 Portal 和 dev 环境日志
SSH_CMD "
if [ '${ENV:-nonprod}' = 'nonprod' ]; then
  docker logs tech-apollo-portal --tail 50
  docker logs tech-apollo-config-dev --tail 50
  docker logs tech-apollo-admin-dev --tail 50
else
  docker logs tech-apollo-config-prod --tail 50
  docker logs tech-apollo-admin-prod --tail 50
fi
docker logs tech-apollo-db --tail 20
"
```

实时跟踪（通过 SSH 管道）：

```bash
# 密码模式
sshpass -p "${SSH_PASSWORD}" ssh -t -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} \
  "docker logs tech-apollo-portal --tail 50 -f"

# 密钥模式
ssh -i ${SSH_KEY_PATH} -t -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} \
  "docker logs tech-apollo-portal --tail 50 -f"
```

## 常见错误日志排查

| 容器 | 日志关键字 | 可能原因 | 处理建议 |
|------|-----------|---------|---------|
| tech-apollo-db | `Can't connect to local MySQL` | MySQL 初始化失败 | 检查数据目录权限，删除后重试 |
| tech-apollo-config-* | `Unable to connect to database` | DB 未就绪 | 等待 DB healthy 后服务会自动重连 |
| tech-apollo-portal | `Connect to admin service failed` | admin service 未启动 | 等待 tech-apollo-admin 就绪 |
| 任意 | `port is already allocated` | 端口冲突 | 修改 .env 中对应端口后重启 |
