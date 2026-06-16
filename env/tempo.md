# Tempo 2.7.0 — 部署报告

| 项目 | 值 |
|------|-----|
| 部署日期 | 2026-03-18 |
| 目标机器 | 192.168.82.93 (Server A) |
| 部署目录 | `/opt/tech-stack/tempo/` |
| 容器名称 | tech-tempo |
| 镜像 | grafana/tempo:2.7.0 |

## 端口

| 端口 | 用途 |
|------|------|
| 3200 | HTTP API（Grafana 数据源） |
| 9411 | Zipkin 兼容接口 |

## 账号密码

无（Tempo 无认证）

## 连接方式

| 方式 | 地址 |
|------|------|
| Ready 检查 | http://tempo.renew.com:3200/ready |
| Grafana 数据源 | `http://tempo.renew.com:3200` (Type: Tempo) |
| OTel Collector 转发 | 由 OTel Collector 通过内部网络转发 |

## 配置

| 参数 | 值 |
|------|-----|
| 数据保留 | 168h (7天) |
| 存储后端 | local (/var/tempo) |
| metrics_generator | service-graphs + span-metrics → prometheus.renew.com:9090 |

## 备注

- Tempo 的 OTLP 端口（4317/4318）不对外暴露，由 OTel Collector 统一接收后转发
- metrics_generator 会将 span metrics 推送到 Prometheus（remote_write）
