# Task 11 — 部署 Prometheus + Alertmanager

- **状态**: ✅ 完成
- **目标机器**: 192.168.82.93
- **Skill**: setup-prometheus
- **前置依赖**: Task 07 (Consul), Task 09 (Tempo), Task 10 (Loki)
- **内存预算**: 1.5G

## 执行内容

1. 执行 `/setup-prometheus start` 部署 Prometheus v3.2 + Alertmanager v0.28
2. 确认 `.env` 配置（2 台方案同机部署，使用 `*.renew.com` 域名默认值即可）
3. 验证指标采集

## .env 关键配置（2 台同机方案 — 全部使用默认域名）

```bash
# 所有服务同在 93 机器，域名由 dnsmasq 解析到本机，无需修改默认值
CONSUL_HOST=consul.renew.com           # 服务发现
RABBITMQ_HOST=rabbitmq.renew.com       # RabbitMQ 指标
MYSQL_EXPORTER_HOST=mysql.renew.com    # MySQL Exporter
REDIS_EXPORTER_HOST=redis.renew.com    # Redis Exporter
MONGODB_EXPORTER_HOST=mongodb.renew.com # MongoDB Exporter
OTEL_COLLECTOR_HOST=otel.renew.com     # OTel Collector 指标
LOKI_HOST=loki.renew.com              # Loki 指标
```

## Skill 命令

```bash
/setup-prometheus start --host 192.168.82.93 --user root --password foxconn.88
/setup-prometheus verify --host 192.168.82.93 --user root --password foxconn.88
```

## 端口说明

- `:9090` — Prometheus Web UI + API
- `:9093` — Alertmanager Web UI

## 验证标准

- [ ] Prometheus 容器运行中
- [ ] `http://prometheus-ui.renew.com` Web UI 可访问（via infra-nginx）
- [ ] Targets 页面显示 Consul 服务发现正常
- [ ] Alertmanager `http://alertmanager.renew.com` 可访问（via infra-nginx）

## 完成记录

- 开始时间:
- 完成时间:
- 备注:
