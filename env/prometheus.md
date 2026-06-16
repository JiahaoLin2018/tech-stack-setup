# Prometheus v3.2 + Alertmanager v0.28 — 部署报告


| 项目   | 值                                                  |
| ---- | -------------------------------------------------- |
| 部署日期 | 2026-03-18                                         |
| 目标机器 | 192.168.82.93 (Server A)                           |
| 部署目录 | `/opt/tech-stack/prometheus/`                      |
| 容器名称 | tech-prometheus / tech-alertmanager                |
| 镜像   | prom/prometheus:v3.2.0 / prom/alertmanager:v0.28.0 |


## 端口


| 端口   | 用途                      |
| ---- | ----------------------- |
| 9090 | Prometheus Web UI + API |
| 9093 | Alertmanager Web UI     |


## 账号密码

无（Prometheus/Alertmanager 无认证）

## 连接方式


| 方式              | 地址                                                                   |
| --------------- | -------------------------------------------------------------------- |
| Prometheus UI   | [http://prometheus-ui.renew.com](http://prometheus-ui.renew.com)（via infra-nginx）/ 直连 `http://prometheus.renew.com:9090` |
| Alertmanager UI | [http://alertmanager.renew.com](http://alertmanager.renew.com)（via infra-nginx）/ 直连 `http://prometheus.renew.com:9093` |
| Grafana 数据源     | `http://prometheus.renew.com:9090` (Type: Prometheus)                |
| Remote Write    | `http://prometheus.renew.com:9090/api/v1/write`                      |


## 采集目标


| Target           | 地址                       | 来源      |
| ---------------- | ------------------------ | ------- |
| Consul SD        | consul.renew.com:8500    | 自动发现微服务 |
| MySQL Exporter   | mysql.renew.com:9104     | 静态配置    |
| Redis Exporter   | redis.renew.com:9121     | 静态配置    |
| MongoDB Exporter | mongodb.renew.com:9216   | 静态配置    |
| RabbitMQ         | rabbitmq.renew.com:15692 | 静态配置    |
| OTel Collector   | otel.renew.com:8888      | 静态配置    |
| Loki             | loki.renew.com:3100      | 静态配置    |


## 配置


| 参数   | 值                                        |
| ---- | ---------------------------------------- |
| 数据保留 | 30d                                      |
| 集群标签 | tech-stack / prod                        |
| 告警规则 | `conf/prometheus/rules/infra-alerts.yml` |


