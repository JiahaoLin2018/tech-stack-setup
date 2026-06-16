# Task 18 — 部署 infra-nginx

- **状态**: ⬜ 待执行
- **目标机器**: 192.168.82.93
- **Skill**: setup-infra-nginx
- **前置依赖**: Task 17 (Harbor 端口迁移完成)

## 目标

部署内部 Web UI 统一入口，提供：
- HTTP 反向代理（:80）：内部管理界面
- TCP 透传（:2222）：GitLab SSH → 97:2222
- TCP 透传（:8082）：Nexus Docker → 97:8082

## Skill 命令

```bash
/setup-infra-nginx start --host 192.168.82.93 --user root --password foxconn.88
/setup-infra-nginx verify --host 192.168.82.93 --user root --password foxconn.88
```

## 代理服务清单

| 域名 | 目标 | 说明 |
|------|------|------|
| grafana.renew.com | 127.0.0.1:3000 | Grafana 仪表盘 |
| gitlab.renew.com | 192.168.82.97:8929 | GitLab Web |
| nexus.renew.com | 192.168.82.97:8081 | Nexus Web |
| harbor.renew.com | 127.0.0.1:8880 | Harbor Registry |
| consul-ui.renew.com | ${CONSUL_HOST}:8500 | Consul UI（直连用 consul.renew.com:8500） |
| apollo.renew.com | ${APOLLO_HOST}:8070 | Apollo Portal |
| prometheus-ui.renew.com | ${PROMETHEUS_HOST}:9090 | Prometheus UI（直连用 prometheus.renew.com:9090） |
| alertmanager.renew.com | ${PROMETHEUS_HOST}:9093 | Alertmanager |
| rabbitmq-ui.renew.com | ${RABBITMQ_HOST}:15672 | RabbitMQ UI |
| dns.renew.com | 127.0.0.1:5380 | dnsmasq UI |

## 验证清单

- [ ] `curl http://192.168.82.93/health` → `{"status":"UP"}`
- [ ] `curl -sI http://grafana.renew.com` → 200（需 DNS 已更新）
- [ ] `ssh -T git@gitlab.renew.com -p 2222` → Welcome to GitLab
- [ ] `docker login 192.168.82.93:8082` → Nexus Docker Registry 可用

## 完成记录

- 开始时间:
- 完成时间:
- 备注:
