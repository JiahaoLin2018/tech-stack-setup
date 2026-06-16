# Task 43 — Loki 生产部署

> 部署生产日志聚合后端（物理孤岛）。对应 architecture-blueprint.md 第五部分阶段四 4-9。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS），hosts.lan 含 `loki-prod.renew.com` |
| 端口 | :3100 / :9096 |

## 架构约束

- B 类，生产物理孤岛独立 1 套
- **生产强制 `LOKI_AUTH_ENABLED=true`**（多租户认证）
- ruler 推送告警到 `alertmanager-prod.renew.com:9093`（task-44 提供）

## 关键配置

| 变量 | prod 值 |
|------|--------|
| `ENV` | `prod` |
| `LOKI_AUTH_ENABLED` | `true`（强制） |
| `ALERTMANAGER_HOST` | `alertmanager-prod.renew.com` |
| `LOKI_MEMORY_LIMIT` | `1g` |

## 部署命令

```bash
/setup-loki start --host <LOKI_PROD_IP> --env prod --user <USER> --password <PASS>
/setup-loki verify --host <LOKI_PROD_IP> --env prod --user <USER> --password <PASS>
```

## 验证标准

- [ ] `curl http://loki-prod.renew.com:3100/ready` 返回 ready（`/ready` `/metrics` 为控制面端点，无需租户头）
- [ ] OTLP 推送：`POST http://loki-prod.renew.com:3100/otlp/v1/logs`（数据面端点，必须带 `X-Scope-OrgID`）
- [ ] 查询接口：`GET http://loki-prod.renew.com:3100/loki/api/v1/labels`（数据面端点，必须带 `X-Scope-OrgID`）
- [ ] `LOKI_AUTH_ENABLED=true` 已生效

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 1 GB | 1-2 核 | 1 TB+ |

## 并行说明

与 task-42（Tempo prod）/ task-41（K3s prod）可并行。

## 注意事项

- 多租户认证开启后，所有客户端（OTel Collector / Grafana / ruler）必须传 `X-Scope-OrgID` 头
- 任务 task-46 OTel Collector prod 配置中需对应设置租户

## 后续步骤

- task-46（OTel Collector prod）以本服务为 Logs 后端
- task-45（Grafana prod）数据源需配置租户头
