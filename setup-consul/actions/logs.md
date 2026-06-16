# action: logs — 查看 Consul 日志

## `--env` 参数处理

```bash
case "${ENV:-dev}" in
  dev|sit|fat|uat|prod) ;;
  *) echo "ERROR: --env 参数无效 '${ENV}'，合法值：dev|sit|fat|uat|prod" && exit 1 ;;
esac
CONTAINER_NAME="tech-consul-${ENV:-dev}"
```

## 步骤

```bash
SSH_CMD "docker logs ${CONTAINER_NAME} --tail 50"
```

实时跟踪（通过 SSH 管道）：

```bash
# 密码模式
sshpass -p "${SSH_PASSWORD}" ssh -t -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} \
  "docker logs ${CONTAINER_NAME} --tail 50 -f"

# 密钥模式
ssh -i ${SSH_KEY_PATH} -t -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} \
  "docker logs ${CONTAINER_NAME} --tail 50 -f"
```

## 常见错误日志排查

| 日志关键字 | 可能原因 | 处理建议 |
|-----------|---------|---------|
| `bind: address already in use` | 端口 8500/8600 被占用 | 修改 .env 中端口或停止占用进程 |
| `data_dir not writable` | 数据目录权限不足 | `chmod 755 /opt/tech-stack/consul-{env}/data` |
| `Failed to connect to gossip layer` | 网络问题 | 检查 DNS 配置是否正确（setup-dns configure） |
