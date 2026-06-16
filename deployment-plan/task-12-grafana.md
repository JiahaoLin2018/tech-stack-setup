# Task 12 — 部署 Grafana

- **状态**: ✅ 完成
- **目标机器**: 192.168.82.93
- **Skill**: setup-grafana
- **前置依赖**: Task 09 (Tempo), Task 10 (Loki), Task 11 (Prometheus)
- **内存预算**: 512M

## 执行内容

1. 执行 `/setup-grafana start` 部署 Grafana 11.4
2. 确认数据源配置（同机，使用默认域名）
3. 验证数据源连接

## .env 关键配置（同机 — 使用默认值）

```bash
PROMETHEUS_HOST=prometheus.renew.com
TEMPO_HOST=tempo.renew.com
LOKI_HOST=loki.renew.com
```

## Skill 命令

```bash
/setup-grafana start --host 192.168.82.93 --user root --password foxconn.88
/setup-grafana verify --host 192.168.82.93 --user root --password foxconn.88
```

## 端口说明

- `:3000` — Grafana Web UI

## 验证标准

- [ ] Grafana 容器运行中
- [ ] `grafana.renew.com:3000` Web UI 可访问
- [ ] Prometheus 数据源连接正常
- [ ] Tempo 数据源连接正常
- [ ] Loki 数据源连接正常

## 完成记录

- 开始时间:
- 完成时间:
- 备注:
