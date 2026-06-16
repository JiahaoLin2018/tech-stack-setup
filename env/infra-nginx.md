# infra-nginx — 部署报告


| 项目   | 值                            |
| ---- | ---------------------------- |
| 部署日期 | 2026-03-31                   |
| 目标机器 | 192.168.82.93                |
| 部署目录 | /opt/tech-stack/infra-nginx/ |
| 容器名称 | tech-infra-nginx             |
| 镜像   | nginx:1.27-alpine            |
| 网络模式 | host                         |


## 端口


| 端口   | 用途                                                 |
| ---- | -------------------------------------------------- |
| 80   | HTTP 反向代理（内部 Web UI）                               |
| 2222 | TCP 透传（GitLab SSH → 192.168.82.97:2222）            |
| 8082 | TCP 透传（Nexus Docker Registry → 192.168.82.97:8082） |


## 代理服务


| 域名                     | 目标                 | 说明              |
| ---------------------- | ------------------ | --------------- |
| grafana.renew.com      | 127.0.0.1:3000     | Grafana 仪表盘     |
| gitlab.renew.com       | 192.168.82.97:8929 | GitLab Web（跨机）  |
| nexus.renew.com        | 192.168.82.97:8081 | Nexus Web（跨机）   |
| harbor.renew.com       | 127.0.0.1:8880     | Harbor Registry |
| consul-ui.renew.com    | ${CONSUL_HOST}:8500     | Consul UI（直连用 consul.renew.com:8500）    |
| apollo.renew.com       | ${APOLLO_HOST}:8070     | Apollo Portal   |
| prometheus-ui.renew.com | ${PROMETHEUS_HOST}:9090 | Prometheus UI（直连用 prometheus.renew.com:9090） |
| alertmanager.renew.com | ${PROMETHEUS_HOST}:9093 | Alertmanager    |
| rabbitmq-ui.renew.com  | ${RABBITMQ_HOST}:15672  | RabbitMQ UI     |
| dns.renew.com          | 127.0.0.1:5380     | dnsmasq UI      |


## 验证结果

- 容器运行正常（healthy）
- 健康检查端点 `/health` 正常
- nginx 配置语法正确
- 端口 :80、:2222、:8082 监听正常
- HTTP 反代本地服务（Grafana、Consul、Prometheus）正常
- HTTP 反代跨机服务（GitLab、Nexus）正常
- TCP 透传端口监听正常

## 备注

- 使用 host 网络模式
- 前置条件：Harbor 已迁移到 :8880
- DNS 更新后域名访问生效
- 部署过程中修复了 proxy_read_timeout 重复定义问题

