# Task 30 — Prometheus 非生产部署

> 部署非生产指标采集 + Alertmanager（K3s 外部独立 Docker Compose）。对应 architecture-blueprint.md 第五部分阶段三 3-7。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS）+ task-11/16/21/26（4 套 Consul nonprod，consul_sd 来源）+ task-28/29（Tempo/Loki，自抓取目标）|
| 端口 | :9090（Prometheus）/ :9093（Alertmanager） |

## 架构约束

- B 类域级共用，nonprod 1 套覆盖 dev/sit/fat/uat
- 必须启用 `--web.enable-remote-write-receiver`（接收 Tempo metrics_generator）
- consul_sd_configs 4 套：`consul-{dev,sit,fat,uat}.renew.com:8500`，过滤 tags: `[metrics]`
- relabel_configs per-job 注入 `env={env}` 标签
- 静态抓取：5 服务 × 4 环境 = 20 个中间件 job + LGT 栈自指标 + OTel Collector :8888
- Alertmanager 与 Prometheus 同 docker-compose；其域名 `alertmanager-nonprod.renew.com` 写入 hosts.lan，被 Loki ruler / Prometheus alerting 跨节点引用

## 关键配置

| 变量 | nonprod 值 |
|------|----------|
| `ENV` | `nonprod` |
| 配置模板（本地源） | `prometheus.nonprod.yml` |
| 远程目标 | `conf/prometheus/prometheus.yml`（上传时重命名） |
| consul_sd | 4 套（dev/sit/fat/uat） |
| Scrape 覆盖 | dev / sit / fat / uat |
| 容器名 | `tech-prometheus-nonprod` / `tech-alertmanager-nonprod` |
| 容器内存 | 2 GB（Prometheus）+ 256 MB（Alertmanager） |

## 部署命令

```bash
/setup-prometheus start --host <PROM_NONPROD_IP> --env nonprod --user <USER> --password <PASS>
/setup-prometheus verify --host <PROM_NONPROD_IP> --env nonprod --user <USER> --password <PASS>
```

## 验证标准

- [ ] `curl http://prometheus-nonprod.renew.com:9090/-/ready` 返回 ready
- [ ] `curl http://alertmanager-nonprod.renew.com:9093/-/ready` 返回 ready
- [ ] Prometheus UI 可访问：`http://prometheus-nonprod-ui.renew.com`（infra-nginx 反代）
- [ ] Alertmanager UI 可访问：`http://alertmanager-nonprod-ui.renew.com`（infra-nginx 反代）
- [ ] consul_sd 已发现 4 套环境的服务（Status → Service Discovery）
- [ ] 中间件 job 全部 UP（mysql-{dev,sit,fat,uat} / redis / mongodb / rabbitmq）
- [ ] `--web.enable-remote-write-receiver` 启用（curl POST `/api/v1/write` 不报 404）

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 2 GB + 256 MB | 1-2 核 | 200 GB |

## 并行说明

- 必须在 task-28（Tempo）/ task-29（Loki）/ task-11/16/21/26（Consul × 4）就绪后启动
- 与 task-31（Grafana）/ task-32（OTel Collector）部署后再启动它们的依赖项

## 注意事项

- alertmanager 直连域名必须在 task-01 hosts.lan 中（蓝图 v1.9.0 修复）
- 业务 Spring Boot 注册到 Consul 时必须打 `metrics` tag，否则不会被 consul_sd 发现
- 抓取失败的 target 不阻塞 Prometheus 启动（仅产出告警）

## 后续步骤

- task-31（Grafana nonprod）依赖本 task（Prometheus 数据源）
- task-32（OTel Collector nonprod）以本服务为 self-metrics 抓取目标
