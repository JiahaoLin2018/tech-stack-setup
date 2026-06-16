# Task 46 — OTel Collector 生产部署

> 部署生产遥测数据网关。对应 architecture-blueprint.md 第五部分阶段四 4-9。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-42（Tempo prod）+ task-43（Loki prod）|
| 端口 | :4317 / :4318 / :8888 / :13133 |

## 架构约束

- B 类，生产物理孤岛独立 1 套
- 业务 Pod 推送 Traces/Logs 到 `otel-prod.renew.com:4317/:4318`
- Collector 路由：Traces → Tempo `:14317` / Logs → Loki `:3100/otlp`
- `resource processor` 透传业务方传入的 `deployment.environment`，仅当上游未传时插入兜底值（`DEPLOYMENT_ENV=prod`）
- Metrics 不经过 Collector（业务 Pod 强制 `OTEL_METRICS_EXPORTER=none`），由 Prometheus 拉取 `/actuator/prometheus`
- :8888 与 edge-nginx 健康检查 :8888 同号，避免同机部署

## 关键配置

| 变量 | prod 值 |
|------|--------|
| `ENV` | `prod` |
| `TEMPO_HOST` | `tempo-prod.renew.com` |
| `LOKI_HOST` | `loki-prod.renew.com` |
| `DEPLOYMENT_ENV` | `prod`（兜底值） |
| `OTEL_MEMORY_LIMIT` | `512m` |

## 部署命令

```bash
/setup-otel-collector start --host <OTEL_PROD_IP> --env prod --user <USER> --password <PASS>
/setup-otel-collector verify --host <OTEL_PROD_IP> --env prod --user <USER> --password <PASS>
```

## 验证标准

- [ ] OTLP gRPC 端口可达：`nc -zv otel-prod.renew.com 4317`
- [ ] `curl http://otel-prod.renew.com:8888/metrics` 返回 Collector 自身指标
- [ ] 健康检查：容器内 `:13133/` 返回 200
- [ ] Tempo 收到示例 trace（生产 K3s Pod 启动后）
- [ ] Loki 收到示例 log（业务 Pod 注入 `deployment.environment=prod`）

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 512 MB | 1 核 | 10 GB |

## 并行说明

必须在 task-42（Tempo prod）/ task-43（Loki prod）就绪后部署。

## 注意事项

- 业务 Pod 通过 task-48 的 `app.sh` 注入 `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-prod.renew.com:4317`
- env 标签注入主通路：app.sh 设置 `OTEL_RESOURCE_ATTRIBUTES=deployment.environment=prod`，Collector 不覆盖

## 后续步骤

- task-48（Runner prod）的 app.sh 默认 OTLP endpoint 指向本服务（env=prod 时）
