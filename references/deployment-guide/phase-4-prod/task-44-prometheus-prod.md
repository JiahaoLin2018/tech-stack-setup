# Task 44 — Prometheus 生产部署

> 部署生产指标采集 + Alertmanager（物理孤岛）。对应 architecture-blueprint.md 第五部分阶段四 4-9。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS）+ task-40（Consul prod）+ task-42/43（Tempo/Loki prod） |
| 端口 | :9090 / :9093 |

## 架构约束

- B 类，生产物理孤岛独立 1 套
- 必须启用 `--web.enable-remote-write-receiver`
- consul_sd_configs 1 套：`consul-prod.renew.com:8500`，过滤 tags: `[metrics]`
- relabel 注入 `env=prod` 标签
- 静态抓取：5 服务 × 1 环境 = 5 个中间件 job + LGT 栈自指标
- Alertmanager 域名 `alertmanager-prod.renew.com` 写入 hosts.lan

## 关键配置

| 变量 | prod 值 |
|------|--------|
| `ENV` | `prod` |
| 配置模板（本地源） | `prometheus.prod.yml` |
| 远程目标 | `conf/prometheus/prometheus.yml`（上传时重命名） |
| consul_sd | 1 套（prod） |
| Scrape 覆盖 | prod |
| 容器名 | `tech-prometheus-prod` / `tech-alertmanager-prod` |
| 容器内存 | 2 GB + 256 MB |

## 部署命令

```bash
/setup-prometheus start --host <PROM_PROD_IP> --env prod --user <USER> --password <PASS>
/setup-prometheus verify --host <PROM_PROD_IP> --env prod --user <USER> --password <PASS>
```

## 验证标准

- [ ] `curl http://prometheus-prod.renew.com:9090/-/ready` 返回 ready
- [ ] `curl http://alertmanager-prod.renew.com:9093/-/ready` 返回 ready
- [ ] Prometheus UI 可访问：`http://prometheus-prod-ui.renew.com`（infra-nginx 跨网段反代）
- [ ] Alertmanager UI 可访问：`http://alertmanager-prod-ui.renew.com`（infra-nginx 跨网段反代）
- [ ] consul_sd 已发现 prod 环境服务
- [ ] 5 个生产中间件 job 全部 UP
- [ ] `--web.enable-remote-write-receiver` 启用（接收 Tempo metrics_generator）

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 2 GB + 256 MB | 1-2 核 | 500 GB+ |

## 并行说明

必须在 task-40（Consul prod）+ task-42/43（Tempo/Loki prod）就绪后启动。

## 注意事项

- alertmanager-prod.renew.com 必须在 task-01 hosts.lan 中
- 生产建议通过 infra-nginx 反代加 basic auth（默认 Prometheus 无认证）

## 后续步骤

- task-45（Grafana prod）依赖本 task
- task-46（OTel Collector prod）以本服务为 self-metrics 抓取目标
