# Grafana 11.4 — 部署报告


| 项目   | 值                          |
| ---- | -------------------------- |
| 部署日期 | 2026-03-18                 |
| 目标机器 | 192.168.82.93 (Server A)   |
| 部署目录 | `/opt/tech-stack/grafana/` |
| 容器名称 | tech-grafana               |
| 镜像   | grafana/grafana:11.4.0     |


## 端口


| 端口   | 用途             |
| ---- | -------------- |
| 3000 | Grafana Web UI |


## 账号密码


| 用户    | 密码                      |
| ----- | ----------------------- |
| admin | GrfAdm_jEXxr5SBwGiFR50K |


## 连接方式


| 方式     | 地址                                                                                               |
| ------ | ------------------------------------------------------------------------------------------------ |
| Web UI | [http://grafana.renew.com:3000](http://grafana.renew.com:3000) (admin / GrfAdm_jEXxr5SBwGiFR50K) |


## 预配置数据源


| 数据源        | 类型         | 地址                                                                   | 状态  |
| ---------- | ---------- | -------------------------------------------------------------------- | --- |
| Prometheus | prometheus | [http://prometheus.renew.com:9090](http://prometheus.renew.com:9090) | ✅   |
| Tempo      | tempo      | [http://tempo.renew.com:3200](http://tempo.renew.com:3200)           | ✅   |
| Loki       | loki       | [http://loki.renew.com:3100](http://loki.renew.com:3100)             | ✅   |


## 数据源联动

- Tempo → Loki：traceId 关联日志
- Tempo → Prometheus：span metrics + service graph
- Loki → Tempo：日志中 traceId 跳转链路

