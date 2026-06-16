# Task 28 — Tempo 非生产部署

> 部署非生产链路追踪后端（K3s 外部独立 Docker Compose）。对应 architecture-blueprint.md 第五部分阶段三 3-7。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS），hosts.lan 含 `tempo-nonprod.renew.com` |
| 端口 | :3200（HTTP 查询 + Metrics）/ :14317（OTLP gRPC，宿主机映射）/ :14318（OTLP HTTP）/ :9411（Zipkin） |

## 架构约束

- B 类域级共用，nonprod 1 套（4 环境共用，env 标签隔离）
- OTel Collector 推送入口走 `:14317/14318`（宿主机映射，避免与同机 OTel Collector :4317 冲突）
- metrics_generator 通过 remote_write 写入 Prometheus（须在 task-30 启用 `--web.enable-remote-write-receiver`）
- env 标签由 OTel Collector 注入 `deployment.environment` 资源属性，Tempo 原生支持

## 关键配置

| 变量 | nonprod 值 |
|------|----------|
| `ENV` | `nonprod` |
| `PROMETHEUS_HOST` | `prometheus-nonprod.renew.com`（remote_write 目标） |
| `PROMETHEUS_PORT` | `9090` |
| `TEMPO_RETENTION` | `168h`（默认 7 天，非生产足够） |
| `TEMPO_MEMORY_LIMIT` | `2g` |

## 部署命令

```bash
/setup-tempo start --host <TEMPO_NONPROD_IP> --env nonprod --user <USER> --password <PASS>
/setup-tempo verify --host <TEMPO_NONPROD_IP> --env nonprod --user <USER> --password <PASS>
```

## 验证标准

- [ ] `curl http://tempo-nonprod.renew.com:3200/ready` 返回 ready
- [ ] OTLP 端口可达：`nc -zv tempo-nonprod.renew.com 14317`
- [ ] 容器名 `tech-tempo-nonprod` Running

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 2 GB | 1-2 核 | 200 GB |

## 并行说明

- 与 task-29（Loki nonprod）可并行（无依赖）
- 与 task-27（K3s）可并行

## 注意事项

- 直连域名 `tempo-nonprod.renew.com` 必须写入 hosts.lan（task-01）
- OTLP 推送端口选用 14317/14318（避免与 OTel Collector :4317/:4318 同机部署冲突）

## 后续步骤

- task-30（Prometheus nonprod）需启用 `--web.enable-remote-write-receiver` 接收 Tempo metrics_generator
- task-32（OTel Collector nonprod）以本服务为 Traces 后端
- task-31（Grafana nonprod）以本服务为 Tempo 数据源
