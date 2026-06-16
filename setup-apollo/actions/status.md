# action: status — 查看 Apollo 状态

## `--env` 参数处理

```bash
case "${ENV:-nonprod}" in
  nonprod|prod) ;;
  *) echo "ERROR: --env 参数无效 '${ENV}'，合法值：nonprod|prod" && exit 1 ;;
esac
```

## 步骤

```bash
SSH_CMD "docker ps --filter name=tech-apollo --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
SSH_CMD "docker stats \$(docker ps --filter name=tech-apollo --format '{{.Names}}' | tr '\n' ' ') --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'"
```

## 预期正常输出

### nonprod 模式（10 容器）

| 容器名 | 状态 | 宿主机端口 |
|--------|------|-----------|
| tech-apollo-db | Up X minutes (healthy) | 0.0.0.0:3307->3306/tcp |
| tech-apollo-portal | Up X minutes (healthy) | 0.0.0.0:8070->8070/tcp |
| tech-apollo-config-dev | Up X minutes (healthy) | 0.0.0.0:8601->8080/tcp |
| tech-apollo-admin-dev | Up X minutes (healthy) | 0.0.0.0:8611->8090/tcp |
| tech-apollo-config-sit | Up X minutes (healthy) | 0.0.0.0:8602->8080/tcp |
| tech-apollo-admin-sit | Up X minutes (healthy) | 0.0.0.0:8612->8090/tcp |
| tech-apollo-config-fat | Up X minutes (healthy) | 0.0.0.0:8603->8080/tcp |
| tech-apollo-admin-fat | Up X minutes (healthy) | 0.0.0.0:8613->8090/tcp |
| tech-apollo-config-uat | Up X minutes (healthy) | 0.0.0.0:8604->8080/tcp |
| tech-apollo-admin-uat | Up X minutes (healthy) | 0.0.0.0:8614->8090/tcp |

### prod 模式（3 容器）

| 容器名 | 状态 | 宿主机端口 |
|--------|------|-----------|
| tech-apollo-db | Up X minutes (healthy) | 0.0.0.0:3307->3306/tcp |
| tech-apollo-config-prod | Up X minutes (healthy) | 0.0.0.0:8605->8080/tcp |
| tech-apollo-admin-prod | Up X minutes (healthy) | 0.0.0.0:8615->8090/tcp |

## 输出解读

| Status 字段 | 含义 |
|-------------|------|
| `Up X minutes (healthy)` | 运行正常 |
| `Up X minutes` | 运行中，健康检查尚未完成 |
| `Up X minutes (unhealthy)` | 运行中但健康检查失败，建议执行 logs |
| `starting` | 正在启动，等待依赖就绪 |
| 无输出 | 容器未运行，执行 start |
