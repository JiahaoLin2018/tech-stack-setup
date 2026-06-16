# action: status — 查看 Consul 状态

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
SSH_CMD "docker ps --filter name=${CONTAINER_NAME} --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
SSH_CMD "docker stats ${CONTAINER_NAME} --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'"
```

## 输出解读

| Status 字段 | 含义 |
|-------------|------|
| `Up X minutes (healthy)` | 运行正常 |
| `Up X minutes` | 运行中，健康检查未完成 |
| `Up X minutes (unhealthy)` | 运行中但健康检查失败，建议执行 logs |
| 无输出 | 容器未运行，执行 start |
