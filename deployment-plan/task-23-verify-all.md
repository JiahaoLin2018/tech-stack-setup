# Task 23 — 全量验证

- **状态**: ⬜ 待执行
- **目标机器**: 192.168.82.93 + 192.168.82.97
- **前置依赖**: Task 20 (K3s 安装完成), Task 21 (DMZ Traefik 部署完成), Task 22 (CI/CD 验证完成)

## 目标

在所有任务完成后，验证整个技术栈的连通性和可用性。

## DNS 层验证

```bash
# 在 93 机器上
dig gitlab.renew.com @192.168.82.93
dig mysql.renew.com @192.168.82.93
dig demo.fat.web.renew.com @192.168.82.93
```

### 检查清单

- [ ] dnsmasq 服务正常
- [ ] 内部域名解析正确
- [ ] 业务域名解析到 97
- [ ] 泛解析生效

## 基础设施层验证

```bash
# 数据存储
mysql -h mysql.renew.com -P 3306 -u root -p -e "SELECT 1"
redis-cli -h redis.renew.com -p 6379 ping

# 服务治理
curl http://consul.renew.com:8500/v1/agent/self
curl http://apollo-config-dev.renew.com/health   # DEV Config（各环境：apollo-config-{env}.renew.com）

# 可观测性
curl http://grafana.renew.com/api/health
curl http://prometheus.renew.com/-/healthy
```

### 检查清单

- [ ] MySQL 连接正常
- [ ] Redis 连接正常
- [ ] MongoDB 连接正常
- [ ] RabbitMQ 连接正常
- [ ] Consul 服务注册正常
- [ ] Apollo 配置获取正常

## 内部入口验证

```bash
# infra-nginx
curl http://192.168.82.93/health

# Web UI 访问
curl -sI http://gitlab.renew.com
curl -sI http://grafana.renew.com
curl -sI http://harbor.renew.com

# TCP 透传
ssh -T git@gitlab.renew.com -p 2222
docker login 192.168.82.93:8082
```

### 检查清单

- [ ] infra-nginx 运行正常
- [ ] 所有 Web UI 通过域名可访问
- [ ] TCP stream 透传正常

## K3s 集群验证

```bash
# 集群状态
kubectl get nodes
kubectl get pods -A

# 资源使用
kubectl top nodes
kubectl top pods -A

# DNS 解析（在 Pod 内）
kubectl run test-dns --image=busybox --rm -it -- nslookup mysql.renew.com
```

### 检查清单

- [ ] K3s 节点状态 Ready
- [ ] 所有 Pod 运行正常
- [ ] HPA 自动扩缩容正常
- [ ] Ingress 域名访问正常

## 业务应用验证

```bash
# 前端访问
curl http://demo.fat.web.renew.com

# API 访问（如部署）
curl http://demo.fat.api.renew.com/actuator/health
```

### 检查清单

- [ ] 前端应用访问正常
- [ ] Gateway 路由正常（如部署）
- [ ] 微服务连接基础设施正常
- [ ] 全链路请求验证通过

## 完整验证清单汇总

### 93 机器

| 服务 | 验证命令 | 状态 |
|------|---------|------|
| dnsmasq | `dig mysql.renew.com @192.168.82.93` | ⬜ |
| MySQL | `mysql -h mysql.renew.com -e "SELECT 1"` | ⬜ |
| Redis | `redis-cli -h redis.renew.com ping` | ⬜ |
| MongoDB | `mongosh mongodb.renew.com:27017` | ⬜ |
| RabbitMQ | `curl rabbitmq.renew.com:15672` | ⬜ |
| Consul | `curl consul.renew.com:8500/v1/agent/self` | ⬜ |
| Apollo | `curl apollo-config-dev.renew.com/health` (DEV Config) | ⬜ |
| Tempo | `curl tempo.renew.com:3200/ready` | ⬜ |
| Loki | `curl loki.renew.com:3100/ready` | ⬜ |
| Prometheus | `curl prometheus.renew.com/-/healthy` | ⬜ |
| Grafana | `curl grafana.renew.com/api/health` | ⬜ |
| OTel Collector | `curl otel.renew.com:8888/metrics` | ⬜ |
| Harbor | `curl harbor.renew.com` | ⬜ |
| infra-nginx | `curl 192.168.82.93/health` | ⬜ |
| K3s | `kubectl get nodes` | ⬜ |

### 97 机器

| 服务 | 验证命令 | 状态 |
|------|---------|------|
| GitLab | `curl gitlab.renew.com` | ⬜ |
| Nexus | `curl nexus.renew.com` | ⬜ |
| Traefik | `curl 192.168.82.97/ping` | ⬜ |

### 跨机连通性

| 测试项 | 命令 | 状态 |
|--------|------|------|
| 97→93 DNS 解析 | `nslookup mysql.renew.com` (on 97) | ⬜ |
| 97→93 MySQL 连接 | `mysql -h mysql.renew.com -P 3306` | ⬜ |
| 业务域名解析 | `dig demo.fat.web.renew.com` | ⬜ |

### 资源检查

| 机器 | 检查项 | 预期 | 状态 |
|------|--------|------|------|
| 93 | 内存使用 | used < 14G | ⬜ |
| 93 | 磁盘使用 | used < 70G | ⬜ |
| 93 | 负载 | load < 4.0 | ⬜ |
| 97 | 内存使用 | used < 7G | ⬜ |
| 97 | 磁盘使用 | used < 50G | ⬜ |
| 97 | 负载 | load < 2.0 | ⬜ |

## 完成记录

- 开始时间:
- 完成时间:
- 全部通过: ⬜
- 备注:
