# Task 32 — OTel Collector 非生产部署

> 部署非生产遥测数据网关（K3s 外部独立 Docker Compose）。对应 architecture-blueprint.md 第五部分阶段三 3-7。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-28/29（Tempo/Loki，作为后端） |
| 端口 | :4317（OTLP gRPC）/ :4318（OTLP HTTP）/ :8888（自身 Metrics）/ :13133（健康检查，仅容器内）|

## 架构约束

- B 类域级共用
- 业务 Pod 推送 Traces/Logs 到 `otel-nonprod.renew.com:4317/:4318`
- Collector 路由：Traces → Tempo `:14317` / Logs → Loki `:3100/otlp`
- `resource processor` 透传业务方传入的 `deployment.environment`，仅当上游未传时插入兜底值（`DEPLOYMENT_ENV=nonprod`）
- Metrics 不经过 Collector（业务 Pod 强制 `OTEL_METRICS_EXPORTER=none`），由 Prometheus 拉取 `/actuator/prometheus`
- :8888 与 edge-nginx 健康检查 :8888 同号，避免同机部署

## 关键配置

| 变量 | nonprod 值 |
|------|----------|
| `ENV` | `nonprod` |
| `TEMPO_HOST` | `tempo-nonprod.renew.com` |
| `LOKI_HOST` | `loki-nonprod.renew.com` |
| `DEPLOYMENT_ENV` | `nonprod`（兜底值） |
| `OTEL_MEMORY_LIMIT` | `512m` |

## 部署命令

```bash
/setup-otel-collector start --host <OTEL_NONPROD_IP> --env nonprod --user <USER> --password <PASS>
/setup-otel-collector verify --host <OTEL_NONPROD_IP> --env nonprod --user <USER> --password <PASS>
```

## 验证标准

- [ ] OTLP gRPC 端口可达：`nc -zv otel-nonprod.renew.com 4317`
- [ ] `curl http://otel-nonprod.renew.com:8888/metrics` 返回 Collector 自身指标
- [ ] 健康检查：容器内 `:13133/` 返回 200
- [ ] Tempo 收到示例 trace：`tempo-nonprod.renew.com:3200/api/search?tags=service.name=test`
- [ ] Loki 收到示例 log：通过 Grafana Logs Explore 查询

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 512 MB | 1 核 | 10 GB |

## 并行说明

- 必须在 task-28（Tempo）/ task-29（Loki）就绪后部署
- 与 task-31（Grafana）可并行

## 注意事项

- 业务 Pod 通过 task-33 的 `app.sh` 注入 `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-nonprod.renew.com:4317`
- env 标签注入主通路：app.sh 设置 `OTEL_RESOURCE_ATTRIBUTES=deployment.environment={env}`，Collector 不覆盖

## 后续步骤

- task-33（Runner nonprod）的 app.sh 默认 OTLP endpoint 指向本服务
- task-34（CI/CD demo）端到端验证完整 Traces/Logs 链路
