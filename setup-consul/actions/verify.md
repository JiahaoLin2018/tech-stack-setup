# action: verify — 验证 Consul

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
SSH_CMD "docker exec ${CONTAINER_NAME} consul members"
SSH_CMD "docker exec ${CONTAINER_NAME} consul operator raft list-peers"
```

## 预期正常输出示例

```
Node                  Address         Status  Type    Build   Protocol  DC   Partition  Segment
tech-consul-{env}     172.x.x.x:8301  alive   server  1.20.x  2         dc1  default    <all>
```

## 故障排查

| 问题 | 可能原因 | 处理建议 |
|------|---------|---------|
| `Error connecting to Consul agent` | 容器未启动 | 执行 `/setup-consul start --env {env}` |
| Leader 返回空 | 集群选举未完成 | 等待 10 秒后重试 |
