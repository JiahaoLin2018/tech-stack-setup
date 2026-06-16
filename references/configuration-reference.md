# 配置参考

> **本文档定位**：跨服务连接清单、环境变量全表、多环境配置差异。
> 网络拓扑见 [网络架构](network-architecture.md)；架构权威见 [architecture-blueprint.md](../architecture-blueprint.md)。

---

## 跨节点连接清单（含多环境）

所有服务间通信统一使用 `*.renew.com` 域名（铁律二）。

### A 类环境级独立服务（dev/sit/fat/uat/prod 各 1 套）

| 消费方 | 依赖方 | `.env` 变量 | 默认值（域名） | 端口 |
|--------|--------|-----------|---------------|------|
| K3s Pod / 业务微服务 | MySQL | `SPRING_DATASOURCE_URL` | `mysql-{env}.renew.com` | `3306` |
| Prometheus | mysqld_exporter | `MYSQL_EXPORTER_HOST` | `mysql-{env}.renew.com` | `9104` |
| K3s Pod | Redis | `SPRING_DATA_REDIS_HOST` | `redis-{env}.renew.com` | `6379` |
| Prometheus | redis_exporter | `REDIS_EXPORTER_HOST` | `redis-{env}.renew.com` | `9121` |
| K3s Pod | MongoDB | `SPRING_DATA_MONGODB_URI` | `mongodb-{env}.renew.com` | `27017` |
| Prometheus | mongodb_exporter | `MONGODB_EXPORTER_HOST` | `mongodb-{env}.renew.com` | `9216` |
| K3s Pod | RabbitMQ AMQP | `SPRING_RABBITMQ_HOST` | `rabbitmq-{env}.renew.com` | `5672` |
| Prometheus | RabbitMQ Prometheus 插件 | `RABBITMQ_HOST` | `rabbitmq-{env}.renew.com` | `15692` |
| infra-nginx | RabbitMQ Mgmt UI | `RABBITMQ_{ENV}_HOST` × 5 | `rabbitmq-{env}-ui.renew.com` → 实例 | `15672` |
| K3s Pod | Consul | `SPRING_CLOUD_CONSUL_HOST` | `consul-{env}.renew.com` | `8500` |
| Prometheus consul_sd | Consul | static `consul-{env}.renew.com:8500` | `consul-{env}.renew.com` | `8500` |
| infra-nginx | Consul UI | `CONSUL_{ENV}_HOST` × 5 | `consul-{env}-ui.renew.com` → 实例 | `8500` |

### B 类域级共用服务（nonprod / prod 各 1 套）

| 消费方 | 依赖方 | `.env` 变量 | 默认值 | 端口 |
|--------|--------|-----------|--------|------|
| K3s Pod | OTel Collector | `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://otel-{nonprod\|prod}.renew.com:4317` | 4317（gRPC）/ 4318（HTTP） |
| OTel Collector | Tempo | `TEMPO_HOST` | `tempo-{nonprod\|prod}.renew.com` | `14317`（OTLP gRPC，宿主机映射）/ `14318`（OTLP HTTP） |
| OTel Collector | Loki | `LOKI_HOST` | `loki-{nonprod\|prod}.renew.com` | `3100`（OTLP HTTP `/otlp`） |
| Grafana | Prometheus | `PROMETHEUS_HOST` | `prometheus-{nonprod\|prod}.renew.com` | `9090` |
| Grafana | Tempo | `TEMPO_HOST` | `tempo-{nonprod\|prod}.renew.com` | `3200`（HTTP 查询 API） |
| Grafana | Loki | `LOKI_HOST` | `loki-{nonprod\|prod}.renew.com` | `3100` |
| Tempo metrics_generator | Prometheus（remote_write） | `PROMETHEUS_HOST` | `prometheus-{nonprod\|prod}.renew.com` | `9090`（需 `--web.enable-remote-write-receiver`） |
| Loki ruler | Alertmanager | `ALERTMANAGER_HOST` | `alertmanager-{nonprod\|prod}.renew.com` | `9093` |
| Prometheus alerting | Alertmanager | static config | `alertmanager-{nonprod\|prod}.renew.com:9093` | `9093` |
| Prometheus 自抓取 | OTel Collector self | static | `otel-{nonprod\|prod}.renew.com:8888` | `8888` |
| infra-nginx | Grafana / Prom UI / Alert UI | `GRAFANA_{NONPROD\|PROD}_HOST` 等 | 实例 IP | 反代到 :3000 / :9090 / :9093 |
| edge-nginx (DMZ) | K3s Traefik | `K3S_NONPROD_TRAEFIK_HOST` / `K3S_PROD_TRAEFIK_HOST` | `k3s-{nonprod\|prod}.renew.com` | `8083` |
| infra-nginx | K3s Traefik（业务域名内网直达） | 同上 | 同上 | `8083` |

### C 类全局唯一服务（1 套）

| 消费方 | 依赖方 | `.env` 变量 | 默认值 | 端口 |
|--------|--------|-----------|--------|------|
| 所有机器 | dnsmasq | `/etc/resolv.conf` 或 `systemd-resolved` | dnsmasq 节点 IP | `53` |
| K3s CoreDNS | dnsmasq（forward） | `${DNS_SERVER_IP}` envsubst 进 `coredns-custom.yaml.tpl` | dnsmasq 节点 IP | `53` |
| dnsmasq | 上游公网 DNS | `UPSTREAM_DNS_PRIMARY` / `UPSTREAM_DNS_SECONDARY` | `114.114.114.114` / `8.8.8.8` | `53` |
| dnsmasq（泛解析兜底） | infra-nginx | `INFRA_NGINX_IP` 进 `dnsmasq.conf address=/.renew.com/` | infra-nginx 节点 IP | `80` |
| infra-nginx | GitLab | `GITLAB_HOST` / `GITLAB_SSH_PORT` | `gitlab.renew.com` / `2222` | HTTP `8929` / SSH `2222` |
| infra-nginx | Nexus | `NEXUS_HOST` / `NEXUS_DOCKER_PORT` | `nexus.renew.com` / `8082` | HTTP `8081` / Docker `8082` |
| infra-nginx | Harbor | `HARBOR_HOST` | `harbor.renew.com` | `8880` |
| infra-nginx | dnsmasq Web UI | `DNS_HOST` | `dns.renew.com` | `5380` |
| K3s containerd | Harbor mirror | `/etc/rancher/k3s/registries.yaml` | `harbor.renew.com` HTTP | `80` |
| 各机器 Docker daemon | Harbor mirror | `daemon.json insecure-registries` | `["harbor.renew.com"]` | — |
| GitLab Runner | GitLab | `GITLAB_URL` | `https://gitlab.renew.com/` | `443`/`8443` |

### D 类 Apollo 合并部署

| 消费方 | 依赖方 | `.env` 变量 | 默认值 | 说明 |
|--------|--------|-----------|--------|------|
| Spring Boot 微服务 | Apollo Config Service | `apollo.meta`（app.sh 注入） | `http://apollo-config-{env}.renew.com` | env: dev/sit/fat/uat/prod，5 套独立 Meta Server |
| infra-nginx | Apollo Portal | `APOLLO_HOST` | nonprod 节点 IP | 反代 `apollo.renew.com` → `:8070` |
| infra-nginx | Apollo Config nonprod | `APOLLO_HOST` | nonprod 节点 IP | 反代 `apollo-config-{dev,sit,fat,uat}.renew.com` → `:8601-8604` |
| infra-nginx | Apollo Config prod | `APOLLO_PROD_HOST` | prod 节点 IP | 反代 `apollo-config-prod.renew.com` → `:8605`（生产网段独立机器） |
| Apollo Portal | 生产 Config Meta Server | Portal 配置 `PRO_META` | `http://apollo-config-prod.renew.com` | 跨网段挂载，Portal 统一管理生产配置但后端 MySQL 完全隔离 |
| Apollo nonprod 容器 | 内置 MySQL | Compose 内部 `apollo-db:3306` | — | nonprod 一个 Compose 拉起 10 容器（MySQL + Portal + 4 Config + 4 Admin） |
| Apollo prod 容器 | 内置 MySQL（独立） | Compose 内部 | — | prod 一个 Compose 拉起 3 容器（MySQL + Config + Admin） |

### CI/CD 链路（B 类 Runner + E 类 setup-cicd）

| 消费方 | 依赖方 | 配置 / 路径 | 说明 |
|--------|--------|-----------|------|
| GitLab Runner | GitLab | `RUNNER_REGISTRATION_TOKEN`（glrt- 格式） | 主动外连，无入站端口 |
| Runner CI Job | Harbor | sed 替换 `HARBOR_PASSWORD` 进 `app.sh` | 镜像构建产物推送 |
| Runner CI Job | Nexus | sed 替换 `NEXUS_PASSWORD` 进 `settings.xml` | Maven 镜像所有请求 |
| Runner CI Job | K3s | volumes 挂载 `kubeconfig` | `app.sh kubectl apply` |
| 业务 Pod（agent 模式） | OTel Java Agent jar | volumes 挂载 `/opt/tech-stack/cicd/opentelemetry-javaagent.jar:ro` | v2.26.1，setup-gitlab-runner 统一管理；跨 JDK 8~21 通用 |
| 业务 Pod | env 标签注入 | `OTEL_RESOURCE_ATTRIBUTES=deployment.environment=${env},service.namespace=${env}` | LGT 环境隔离主通路 |
| 业务 Pod | OTel Endpoint | `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-${domainEnv}.renew.com:4317` | env→domainEnv：dev/sit/fat/uat→nonprod；prod→prod |
| 业务 Pod | Apollo Meta | `JAVA_OPTS=-Dapollo.meta=http://apollo-config-${env}.renew.com` | env 实际环境名 |
| 业务 Pod | Metrics 通路 | `OTEL_METRICS_EXPORTER=none` | 强制关闭 OTLP 指标，由 Prometheus 拉取 `/actuator/prometheus` |

---

## 服务访问方式总表

| 服务 | 访问方式 | URL / 命令 |
|------|---------|-----------|
| **全局唯一** |||
| GitLab Web | infra-nginx 反代 | `http://gitlab.renew.com` |
| GitLab SSH | infra-nginx TCP 透传 | `ssh -p 2222 git@gitlab.renew.com` |
| Nexus Web / Maven API | infra-nginx 反代 | `http://nexus.renew.com` / `http://nexus.renew.com/repository/maven-public/` |
| Nexus Docker Registry | infra-nginx TCP 透传 | `docker login nexus.renew.com:8082` |
| Harbor Web + Registry | infra-nginx 反代 | `http://harbor.renew.com`（需 Docker `insecure-registries: ["harbor.renew.com"]`） |
| dnsmasq Web UI | infra-nginx 反代 | `http://dns.renew.com` |
| **域级共用 UI** |||
| Grafana nonprod / prod | infra-nginx 反代 | `http://grafana-{nonprod\|prod}-ui.renew.com` |
| Prometheus UI | infra-nginx 反代 | `http://prometheus-{nonprod\|prod}-ui.renew.com` |
| Alertmanager UI | infra-nginx 反代 | `http://alertmanager-{nonprod\|prod}-ui.renew.com` |
| **域级直连数据端口** |||
| OTel Collector OTLP | Pod 直连 | `otel-{nonprod\|prod}.renew.com:4317`（gRPC）/ `:4318`（HTTP） |
| Tempo（OTel 推送 / Grafana 查询） | 直连 | 推送 `tempo-{nonprod\|prod}.renew.com:14317` / 查询 `:3200` |
| Loki（OTel 推送 / Grafana 查询） | 直连 | 推送 `loki-{nonprod\|prod}.renew.com:3100/otlp` / 查询 `:3100` |
| Prometheus（直连查询 / remote_write） | 直连 | `prometheus-{nonprod\|prod}.renew.com:9090` |
| Alertmanager（Loki ruler / Prometheus alerting 推送） | 直连 | `alertmanager-{nonprod\|prod}.renew.com:9093` |
| K3s Traefik Ingress（业务流量后端） | edge-nginx / infra-nginx 转发 | `k3s-{nonprod\|prod}.renew.com:8083` |
| **非生产独有** |||
| Apollo Portal | infra-nginx 反代 | `http://apollo.renew.com`（默认 apollo/admin，首次登录修改） |
| **环境级直连** |||
| MySQL × 5 | Pod 直连 | `mysql -h mysql-{env}.renew.com -P 3306` |
| Redis × 5 | Pod 直连 | `redis-cli -h redis-{env}.renew.com -p 6379 -a <pass>` |
| MongoDB × 5 | Pod 直连 | `mongosh "mongodb://admin:<pass>@mongodb-{env}.renew.com:27017/admin"` |
| RabbitMQ AMQP × 5 | Pod 直连 | `rabbitmq-{env}.renew.com:5672` |
| Consul API × 5 | Pod 直连 / consul_sd | `consul-{env}.renew.com:8500` |
| **环境级 Web UI** |||
| Consul UI × 5 | infra-nginx 反代 | `http://consul-{env}-ui.renew.com` |
| RabbitMQ Mgmt UI × 5 | infra-nginx 反代 | `http://rabbitmq-{env}-ui.renew.com` |
| Apollo Config × 5 | Spring Boot apollo.meta | `http://apollo-config-{env}.renew.com`（含 prod 跨网段） |
| **业务应用** |||
| 前端（K3s）| edge-nginx (DMZ) → Traefik | `https://{project}.{env}.web.renew.com` |
| API（K3s）| edge-nginx (DMZ) → Traefik | `https://{project}.{env}.api.renew.com` |

---

## 多环境配置差异

### 环境级独立服务（A 类）资源差异

| 服务 | dev | sit | fat | uat | prod |
|------|-----|-----|-----|-----|------|
| MySQL 容器内存 | 1g | 1g | 2g | 2g | 4g |
| MySQL InnoDB Buffer Pool | 700M | 700M | 1.4G | 1.4G | 2.8G |
| Redis maxmemory / 容器内存 | 512mb / 1g | 512mb / 1g | 1g / 2g | 1g / 2g | 2g / 4g |
| MongoDB 容器内存 / WiredTiger Cache | 1g / 0.5 | 1g / 0.5 | 2g / 1 | 2g / 1 | 4g / 2 |
| RabbitMQ 容器内存 | 512m | 512m | 1g | 1g | 2g |
| Consul ACL | 关闭 | 关闭 | 关闭 | 关闭 | **必须开启** |
| Consul Gossip 加密 | 建议 | 建议 | 建议 | 建议 | **必须开启** |

### 域级共用服务（B 类）配置差异

| 服务 | nonprod | prod |
|------|---------|------|
| LOKI_AUTH_ENABLED | `false` | **`true`**（强制多租户认证） |
| Prometheus 抓取目标 | 4 套 spring-boot-{env} consul_sd + 16 中间件 Exporter（mysql/redis/mongodb/rabbitmq × 4 环境）+ 4 域级（otel/loki/tempo/alertmanager-nonprod） | 1 套 spring-boot consul_sd + 4 中间件 + 4 域级（含 alertmanager-prod 自抓取） |
| K3s Namespace | `dev` / `sit` / `fat` / `uat` | `prod` |
| GitLab Runner tag | `non-prod` | `prod` |
| edge-nginx 处理域名 | `*.{dev,sit,fat,uat}.{web,api}.renew.com` | `*.prod.{web,api}.renew.com` |
| edge-nginx 后端 K3s | `k3s-nonprod.renew.com:8083` | `k3s-prod.renew.com:8083` |
| edge-nginx SSL 证书 | 测试证书 | 生产证书 |
| edge-nginx 部署阶段 | 阶段三 3-12（可选） | 阶段五 5-1（必需） |

### Apollo（D 类）容器差异

| 模式 | 容器数 | 端口 | 数据库 Schema | 部署阶段 |
|------|-------|------|-------------|---------|
| nonprod（合并 10 容器） | 1 MySQL + 1 Portal + 4 Config + 4 Admin | Portal :8070 / Config :8601-8604 / Admin :8611-8614 | `ApolloPortalDB` + `ApolloConfigDB_dev/sit/fat/uat` | 阶段二 2-1 |
| prod（合并 3 容器） | 1 MySQL（独立物理实例）+ 1 Config + 1 Admin | Config :8605 / Admin :8615 | `ApolloConfigDB_prod` | 阶段四 4-6 |

---

## env→domainEnv 映射（app.sh 自动转换）

```
app.sh 接收 ${env}（dev/sit/fat/uat/prod 之一）
   │
   ▼
case ${env} in
  prod)  domainEnv=prod ;;
  *)     domainEnv=nonprod ;;
esac
   │
   ▼
注入业务 Pod 环境变量：
  OTEL_EXPORTER_OTLP_ENDPOINT = http://otel-${domainEnv}.renew.com:4317
  OTEL_RESOURCE_ATTRIBUTES    = deployment.environment=${env},service.namespace=${env}
  apollo.meta                  = http://apollo-config-${env}.renew.com
  SPRING_PROFILES_ACTIVE       = ${env}
```

---

## 密码与凭据生成规则

按 `{服务缩写}{角色}_{16位随机大小写字母+数字}` 规则生成（详见 [部署原则 §8](deployment-principles.md)）。所有密码记录在 `env/<service>.md`（禁止入 git）。

| 服务 | 密码字段 | 服务缩写 / 角色 |
|------|---------|--------------|
| dnsmasq | `DNS_WEB_PASSWORD` | `Dns` / `Adm` |
| MySQL | `MYSQL_ROOT_PASSWORD` / `MYSQL_APP_PASSWORD` / `MYSQL_EXPORTER_PASSWORD` | `Mys` / `Root` `App` `Exp` |
| Redis | `REDIS_PASSWORD` / `REDIS_APP_PASSWORD` / `REDIS_EXPORTER_PASSWORD` | `Rds` / `Default` `App` `Exp` |
| MongoDB | `MONGO_ROOT_PASSWORD` / `MONGO_APP_PASSWORD` / `MONGO_EXPORTER_PASSWORD` | `Mgo` / `Root` `App` `Exp` |
| RabbitMQ | `RABBITMQ_PASSWORD` | `Rmq` / `Adm` |
| Apollo | Apollo 内置 MySQL `root` 密码 + Portal admin | `Apo` / `Db` |
| Grafana | `GRAFANA_ADMIN_PASSWORD` | `Grf` / `Adm` |
| Harbor | `HARBOR_ADMIN_PASSWORD` / Harbor 内置 PostgreSQL 密码 | `Hbr` / `Adm` `Db` |
| Nexus | 自动生成首次密码（`/nexus-data/admin.password`） | — |

---

## 配置项快速索引

| 想知道 | 看这里 |
|-------|-------|
| 某个服务部署到哪台机器 | `deployment-plan/README.md`（动态生成）+ `env/<service>.md` |
| 某个 `.env` 变量从哪来到哪去 | 本文「跨节点连接清单」 |
| 跨服务通信链路 | [网络架构 — 双入口流量路径](network-architecture.md#双入口流量路径) |
| 多环境隔离策略 | [架构蓝图 §1.1 隔离粒度速查表](../architecture-blueprint.md) |
| `--env` 参数契约 | [架构蓝图附录 B.2](../architecture-blueprint.md) |
| 五阶段部署顺序 | [架构蓝图第五部分](../architecture-blueprint.md) + [CLAUDE.md 部署顺序](../CLAUDE.md#部署顺序五阶段) |
| 资源 / 高可用 / 备份 | [资源规划](resource-planning.md) |
| 可观测性数据流 | [可观测性数据流](observability-pipeline.md) |
| 业务接入 | [setup-cicd/actions/integrate.md](../setup-cicd/actions/integrate.md) |
