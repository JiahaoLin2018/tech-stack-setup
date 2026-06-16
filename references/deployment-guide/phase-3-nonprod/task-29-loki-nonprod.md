# Task 29 — Loki 非生产部署

> 部署非生产日志聚合后端（K3s 外部独立 Docker Compose）。对应 architecture-blueprint.md 第五部分阶段三 3-7。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS），hosts.lan 含 `loki-nonprod.renew.com` |
| 端口 | :3100（HTTP API + OTLP HTTP 推送 + Grafana 查询 + 自身 Metrics） / :9096（gRPC 内部） |

## 架构约束

- B 类域级共用
- 原生 OTLP 接收（`/otlp` endpoint），通过 `otlp_config.resource_attributes` 自动索引 `deployment.environment` → `deployment_environment` 标签实现 4 环境逻辑隔离
- ruler 推送告警到 `alertmanager-nonprod.renew.com:9093`（task-30 提供）
- nonprod 默认 `auth_enabled: false`（生产 task-43 强制 true）

## 关键配置

| 变量 | nonprod 值 |
|------|----------|
| `ENV` | `nonprod` |
| `LOKI_AUTH_ENABLED` | `false` |
| `ALERTMANAGER_HOST` | `alertmanager-nonprod.renew.com` |
| `LOKI_MEMORY_LIMIT` | `1g` |

## 部署命令

```bash
/setup-loki start --host <LOKI_NONPROD_IP> --env nonprod --user <USER> --password <PASS>
/setup-loki verify --host <LOKI_NONPROD_IP> --env nonprod --user <USER> --password <PASS>
```

## 验证标准

- [ ] `curl http://loki-nonprod.renew.com:3100/ready` 返回 ready
- [ ] `curl http://loki-nonprod.renew.com:3100/metrics` 返回自身指标
- [ ] OTLP 推送端点：`POST http://loki-nonprod.renew.com:3100/otlp/v1/logs`

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 1 GB | 1-2 核 | 500 GB（按日志量调整）|

## 并行说明

- 与 task-28（Tempo nonprod）可并行
- 与 task-27（K3s）可并行

## 注意事项

- 直连域名必须写入 hosts.lan
- ruler 告警需 task-30 部署后才能真正送达 Alertmanager（部署顺序无严格要求，本 task 启动时仅告警暂存）

## 后续步骤

- task-32（OTel Collector nonprod）以本服务为 Logs 后端
- task-31（Grafana nonprod）以本服务为 Loki 数据源
