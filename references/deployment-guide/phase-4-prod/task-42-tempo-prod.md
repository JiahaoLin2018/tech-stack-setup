# Task 42 — Tempo 生产部署

> 部署生产链路追踪后端（物理孤岛）。对应 architecture-blueprint.md 第五部分阶段四 4-9。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS），hosts.lan 含 `tempo-prod.renew.com` |
| 端口 | :3200 / :14317 / :14318 / :9411 |

## 架构约束

- B 类，生产物理孤岛独立 1 套
- 与非生产 Tempo（task-28）网络物理隔离
- metrics_generator 通过 remote_write 写入 `prometheus-prod.renew.com:9090`

## 关键配置

| 变量 | prod 值 |
|------|--------|
| `ENV` | `prod` |
| `PROMETHEUS_HOST` | `prometheus-prod.renew.com` |
| `PROMETHEUS_PORT` | `9090` |
| `TEMPO_RETENTION` | `168h`（默认 7 天）— 如有合规审计需求可延长（如 `720h`/30 天，注意磁盘容量同步扩容） |
| `TEMPO_MEMORY_LIMIT` | `2g` |

## 部署命令

```bash
/setup-tempo start --host <TEMPO_PROD_IP> --env prod --user <USER> --password <PASS>
/setup-tempo verify --host <TEMPO_PROD_IP> --env prod --user <USER> --password <PASS>
```

## 验证标准

- [ ] `curl http://tempo-prod.renew.com:3200/ready` 返回 ready
- [ ] OTLP 端口可达：`nc -zv tempo-prod.renew.com 14317`
- [ ] 容器名 `tech-tempo-prod` Running

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 2 GB | 1-2 核 | 500 GB+ |

## 并行说明

与 task-43（Loki prod）/ task-41（K3s prod）可并行。

## 后续步骤

- task-44（Prometheus prod）需启用 `--web.enable-remote-write-receiver`
- task-46（OTel Collector prod）以本服务为 Traces 后端
- task-45（Grafana prod）以本服务为 Tempo 数据源
