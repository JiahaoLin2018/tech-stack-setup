# Tech Stack Setup — 项目上下文

> 基于 Docker Compose + K3s 混合架构的 FinTech 级多环境隔离微服务技术栈。
> 每个服务对应一个 `setup-*` skill，通过 SSH（Python paramiko）远程部署。
> 架构权威：[architecture-blueprint.md](architecture-blueprint.md) v1.9.0。本文件是 AI 决策上下文，仅保留跨服务/全局信息。

## 架构总览

```
┌─────────────────────────────────────────────────────────────────────┐
│  全局内网核心区（Global Internal Zone，全局唯一 1 套）                 │
│    网络基座: setup-dns · setup-infra-nginx                          │
│    研发资产: setup-gitlab · setup-nexus · setup-harbor              │
└─────────────────────────────────────────────────────────────────────┘
                  │
        ┌─────────┴──────────┐
        ▼                    ▼
┌──────────────────┐  ┌──────────────────┐
│  非生产域 Non-Prod │  │  生产域 Prod      │
│  共用底座 ×1:     │  │  物理孤岛 ×1:    │
│   K3s/LGT/Runner │  │   K3s/LGT/Runner │
│   Apollo (10 容器) │  │   Apollo (3 容器) │
│  环境级独立 ×4:   │  │  环境级独立 ×1:  │
│   MySQL/Redis/   │  │   MySQL/Redis/   │
│   MongoDB/RMQ/   │  │   MongoDB/RMQ/   │
│   Consul         │  │   Consul         │
│  Dev/SIT/FAT/UAT │  │  Prod            │
└────────┬─────────┘  └─────────┬────────┘
         ▼                      ▼
   DMZ edge-nginx (nonprod)  DMZ edge-nginx (prod)
   独立公网 IP / 独立机房     独立公网 IP / 物理孤岛
```

> **三大逻辑域 + 两条 DMZ 安全边界**。完整设计、隔离粒度速查表、Apollo 全景图见 architecture-blueprint.md 第一/二部分。

## 硬约束

> AI 执行任何操作前必须遵守，违反即为 bug。

| 约束 | 说明 |
|------|------|
| 远程连接 | `actions/*.md` 用 `ssh`/`scp`/`sshpass` 命令展示部署步骤（便于人类阅读）；**AI 实际执行部署时统一通过 Python paramiko 库**调用：远程命令用 `SSHClient.exec_command()`、文件上传用 `SFTPClient.put()`，禁止把 actions 里的命令字符串直接 shell 执行 |
| 文件上传（含 `${VAR}`） | AI 实际执行部署时用 `paramiko.SFTPClient.put()` 文件复制；**禁止** `sftp.open('w')` 字符串写入（会让 shell 在远端展开 `${VAR}` 致密码/路径变量为空） |
| 配置渲染 | 普通服务用 `.tpl` + `envsubst`；**Nginx 服务（infra-nginx / edge-nginx）禁止 envsubst**，必须用 Python 正则替换（防止吞掉 `$host` `$remote_addr` 等内置变量） |
| DNS 优先 | dnsmasq 是整个架构基石，必须**最先部署**并在每台机器配置 DNS 指向 |
| 域名替代 IP | 除以下 4 类合理例外外，所有配置/文档/脚本禁止硬编码 IP：① `setup-dns` 的 `hosts.lan`（DNS 映射源）② `setup-infra-nginx` upstream 后端（避免循环依赖）③ `setup-k3s` CoreDNS 转发目标（转发目标本身就是 DNS 服务器 IP）④ K3s `kubeconfig` 中 API Server 地址（K3s 内部组件通信） |
| 密码占位符 | 所有密码使用 `CHANGE_ME_*` 占位符，部署前必须替换 |
| `.env` 安全 | 包含敏感信息，已 `.gitignore`，禁止提交 |
| K3s 定位 | **仅作无状态业务应用运行底座**（前端 / Gateway / Spring Boot 微服务），所有中间件 / LGT 栈 / Apollo / GitLab Runner 全部在 K3s **外部**独立 Docker Compose |
| 干净服务器假设 | `setup-*` 遇到端口/资源冲突只检测和通知，不做系统级修改 |

## 服务注册表

> 多环境部署次数与 `--env` 契约见 architecture-blueprint.md 附录 B（B.1 部署次数 + B.2 6 类参数契约）。

| 分层 | 服务 | Skill | 版本 | 端口 | 域名 | 用途 |
|------|------|-------|------|------|------|------|
| **全局共享层** ||||||
| DNS | dnsmasq | `setup-dns` | latest | 53 / 5380 | `dns.renew.com`（Web UI） | 局域网 *.renew.com 域名解析，架构基石，最先部署 |
| 内部入口 | infra-nginx | `setup-infra-nginx` | nginx 1.27 | 80 / 2222 / 8082 | 无（代理入口） | 内部 Web UI 统一反代入口；`*.{env}` 业务域名按 nonprod/prod 双 K3s 分流 |
| 研发支撑 | GitLab EE | `setup-gitlab` | 17.8 | 8929 / 8443 / 2222 | `gitlab.renew.com` | 代码托管 + CI/CD（企业版，含许可证激活） |
| 研发支撑 | Nexus | `setup-nexus` | 3.87 OSS | 8081 / 8082 | `nexus.renew.com` | Maven 私有仓库 + Docker Registry |
| 研发支撑 | Harbor | `setup-harbor` | 2.12 | 8880 | `harbor.renew.com` | Docker 镜像仓库（含 Trivy 漏洞扫描） |
| **环境级独立层（A 类，5 套：dev/sit/fat/uat/prod）** ||||||
| 数据存储 | MySQL | `setup-mysql` | 8.4 LTS | 3306 / 9104(Exporter) | `mysql-{env}.renew.com` | 业务主数据库（与 Apollo 专用 MySQL 完全分离） |
| 数据存储 | Redis | `setup-redis` | 8.0-alpine | 6379 / 9121(Exporter) | `redis-{env}.renew.com` | 缓存 / 分布式锁 / 会话；ACL 三类用户 |
| 数据存储 | MongoDB | `setup-mongodb` | 8.0 | 27017 / 9216(Exporter) | `mongodb-{env}.renew.com` | 文档数据库；启用 `security.authorization` |
| 消息中间件 | RabbitMQ | `setup-rabbitmq` | 4.0-mgmt | 5672 / 15672(UI) / 15692(Metrics) | `rabbitmq-{env}.renew.com`（AMQP）/ `rabbitmq-{env}-ui.renew.com`（UI） | 异步消息 / Quorum Queue |
| 服务治理 | Consul | `setup-consul` | 1.20 | 8500 / 8600 | `consul-{env}.renew.com`（直连）/ `consul-{env}-ui.renew.com`（UI） | 服务注册与发现，作为 Prometheus consul_sd 源 |
| **域级共用层（B 类，2 套：nonprod/prod）** ||||||
| 业务应用 | K3s | `setup-k3s` | v1.32 | 6443 / 8083 | `k3s-{nonprod\|prod}.renew.com:8083` | 业务应用编排平台（前端 / Gateway / 微服务） |
| 可观测性 | OTel Collector | `setup-otel-collector` | 0.120.0 | 4317(gRPC) / 4318(HTTP) / 8888(self) | `otel-{nonprod\|prod}.renew.com` | Traces/Logs 统一接收网关，路由到 Tempo/Loki |
| 可观测性 | Tempo | `setup-tempo` | 2.7.0 | 3200 / 14317 / 14318 | `tempo-{nonprod\|prod}.renew.com` | 分布式链路追踪后端 |
| 可观测性 | Loki | `setup-loki` | 3.5.0 | 3100 | `loki-{nonprod\|prod}.renew.com` | 日志聚合后端，原生 OTLP 接收 |
| 可观测性 | Prometheus + Alertmanager | `setup-prometheus` | v3.2 / v0.28 | 9090 / 9093 | `prometheus-{nonprod\|prod}.renew.com` / `alertmanager-{nonprod\|prod}.renew.com` | 指标采集 + 告警；nonprod 采集 4 套环境，prod 采集 1 套 |
| 可观测性 | Grafana | `setup-grafana` | 11.4 | 3000 | `grafana-{nonprod\|prod}-ui.renew.com`（infra-nginx 反代） | 统一可视化看板（Trace↔Log↔Metrics 三向跳转） |
| 研发支撑 | GitLab Runner | `setup-gitlab-runner` | 17.8 | 无暴露端口 | — | CI/CD 执行器 + CI Job 执行环境一站式部署（含 OTel Agent jar） |
| 接入层 | edge-nginx | `setup-edge-nginx` | nginx 1.27 | 80 / 443 | `*.{env}.{web\|api}.renew.com` | 公网业务流量入口（DMZ 区），nonprod/prod 双实例物理隔离 |
| **D 类合并部署** ||||||
| 服务治理 | Apollo | `setup-apollo` | 2.5.0 + mysql 8.4 | 8070(Portal) / 8601-8605(Config) / 8611-8615(Admin) | `apollo.renew.com`（Portal）/ `apollo-config-{env}.renew.com`（Config） | 分布式配置中心；nonprod 一次拉起 10 容器，prod 一次拉起 3 容器；内置专用 MySQL |
| **E 类业务接入指导** ||||||
| 研发支撑 | CI/CD 接入指导 | `setup-cicd` | — | — | — | demo 端到端验证 + integrate.md 业务接入指南（不部署基础设施，不接受 `--env`） |

## 多环境隔离策略

> 对照 architecture-blueprint.md 附录 B.2 的 6 类 `--env` 参数契约。

| 分类 | 适用 Skill | `--env` 取值 | 默认值 | 实例数 | 隔离策略 |
|------|-----------|------------|-------|-------|---------|
| **A 环境级完全独立** | mysql / redis / mongodb / rabbitmq / consul | `dev\|sit\|fat\|uat\|prod` | `dev` | 各 5 套 | 每环境独立物理实例，无任何数据交集 |
| **B 域级共用 + 生产独立** | k3s / loki / prometheus / tempo / otel-collector / grafana / gitlab-runner / edge-nginx | `nonprod\|prod` | `nonprod` | 各 2 套 | 非生产 4 环境共用 1 套（K3s 用 Namespace 隔离 / LGT 用 `env` 标签隔离），生产物理孤岛独立 1 套 |
| **C 全局唯一** | dns / infra-nginx / gitlab / nexus / harbor | 不接受 | — | 各 1 套 | 跨所有环境共享，传入 `--env` 即报错退出 |
| **D Apollo 特殊合并** | apollo | `nonprod\|prod` | `nonprod` | 2 套 | nonprod ×1（10 容器：Portal + 4 Config + 4 Admin + 1 MySQL）；prod ×1（3 容器：Config + Admin + 1 MySQL）；Apollo 专用 MySQL 内置 |
| **E 业务接入指导** | cicd | 不接受（action: `demo\|integrate`） | — | 0 | 无远程基础设施部署 |

> A/B/D 类 skill 的 `actions/start.md` 必须解析 `--env` 并切换容器名 / 部署目录 / 域名 / `.env`；C/E 类传入 `--env` 立即报错退出。

## 域名寻址

> 四层域名命名规范（对照 architecture-blueprint.md 第三部分）。`*` 表示泛解析。

| 层级 | 规范 | 示例 | 解析方式 | 适用组件 |
|------|------|------|---------|---------|
| ① 全局唯一 | `{service}.renew.com` | `gitlab.renew.com` / `harbor.renew.com` / `dns.renew.com` | 泛解析 → infra-nginx | DNS / infra-nginx UI / GitLab / Nexus / Harbor |
| ② 域级直连数据端口 | `{service}-{nonprod\|prod}.renew.com` | `otel-nonprod.renew.com:4317` / `prometheus-prod.renew.com:9090` | **hosts.lan** 精确匹配 | OTel / Loki / Tempo / Prometheus / Alertmanager / K3s（Pod 直连数据端口） |
| ② 域级共用 UI | `{service}-{nonprod\|prod}-ui.renew.com` | `grafana-nonprod-ui.renew.com` | 泛解析 → infra-nginx | Grafana / Prometheus UI / Alertmanager UI |
| ③ 非生产独有 | `{service}.renew.com`（仅非生产域） | `apollo.renew.com` | 泛解析 → infra-nginx | Apollo Portal |
| ④ 环境级直连 | `{service}-{env}.renew.com` | `mysql-dev.renew.com:3306` | **hosts.lan** 精确匹配 | MySQL / Redis / MongoDB / RabbitMQ / Consul（Pod 直连） |
| ④ 环境级 Web UI | `{service}-{env}-ui.renew.com` | `consul-dev-ui.renew.com` | 泛解析 → infra-nginx | Consul UI / RabbitMQ UI |
| ④ Apollo Config | `apollo-config-{env}.renew.com` | `apollo-config-fat.renew.com` | 泛解析 → infra-nginx | 各环境 Apollo Config Service（含 prod 跨网段） |
| ④ 业务应用 | `{project}.{env}.{web\|api}.renew.com` | `zoro.fat.web.renew.com` | edge-nginx (DMZ) / infra-nginx → K3s Traefik :8083 | K3s 业务前端 / Gateway / 微服务 |

> **速查口诀**：解析方式列标注 **hosts.lan** 的即需写入 `hosts.lan`；其余均为泛解析 → infra-nginx 反代。
> 反代域名访问**不带端口**（如 `http://gitlab.renew.com`）；hosts.lan 直连域名**必须带端口**（如 `mysql-dev.renew.com:3306`）。

### hosts.lan 必备 37 条

```
# ④ 环境级直连 — 5 服务 × 5 环境 = 25 条
mysql-{dev,sit,fat,uat,prod}.renew.com         → 各环境 MySQL IP
redis-{dev,sit,fat,uat,prod}.renew.com         → 各环境 Redis IP
mongodb-{dev,sit,fat,uat,prod}.renew.com       → 各环境 MongoDB IP
rabbitmq-{dev,sit,fat,uat,prod}.renew.com      → 各环境 RabbitMQ IP
consul-{dev,sit,fat,uat,prod}.renew.com        → 各环境 Consul IP

# ② 域级直连 — 6 服务 × 2 域 = 12 条
otel-{nonprod,prod}.renew.com                  → 各域 OTel Collector IP
loki-{nonprod,prod}.renew.com                  → 各域 Loki IP
tempo-{nonprod,prod}.renew.com                 → 各域 Tempo IP
prometheus-{nonprod,prod}.renew.com            → 各域 Prometheus IP
alertmanager-{nonprod,prod}.renew.com          → 各域 Alertmanager IP（Loki ruler / Prometheus alerting 推送 :9093）
k3s-{nonprod,prod}.renew.com                   → 各域 K3s 集群节点 IP（edge-nginx / infra-nginx 转发目标）
```

### DNS 解析链路

```
K3s Pod 查询 mysql-fat.renew.com
     │
     ▼
K3s CoreDNS（匹配 .renew.com）
     │
     ▼
转发到 dnsmasq (:53)         ← coredns-custom.yaml.tpl 配置 forward 到 ${DNS_SERVER_IP}
     │
     ▼
hosts.lan 精确匹配 → 返回 FAT MySQL IP
     │
     ▼
Pod 直连 mysql-fat.renew.com:3306（不再经过 DNS）
```

## 部署顺序（五阶段）

> 对照 architecture-blueprint.md 第五部分。同阶段任务可并行；阶段间严格串行。

| 阶段 | 任务编号 | 部署内容 | 关键说明 |
|------|---------|---------|---------|
| **一 全局基建** | 1-1 | `setup-dns` | DNS 必须最先部署，所有域名解析基础 |
| | 1-2 | `setup-infra-nginx` | 部署前**预配置全部反代规则**（含尚未部署的服务），后续上游就绪即生效（502 不影响 nginx） |
| | 1-3 ~ 1-5 | `setup-gitlab` / `setup-nexus` / `setup-harbor` | 三者无相互依赖，**全部并行** |
| **二 配置中心** | 2-1 | `setup-apollo --env nonprod` | **一次拉起 10 容器**：MySQL + Portal + 4 环境 Config/Admin |
| **三 非生产建设** | 3-1 ~ 3-5 | mysql/redis/mongodb/rabbitmq/consul × 4 nonprod env | dev/sit/fat/uat 各环境中间件，独立机器并行 |
| | 3-6 | `setup-k3s --env nonprod` | 配置 CoreDNS 转发 `.renew.com` 到 dnsmasq；4 Namespace |
| | 3-7 | LGT nonprod（tempo / loki / prometheus / grafana / otel-collector --env nonprod） | 顺序：tempo + loki → prometheus → grafana + otel-collector |
| | 3-8 | `setup-gitlab-runner --env nonprod` | 一站式：静态工具 + app.sh + kubeconfig + OTel Agent jar + Runner 启动 + Harbor 推送基础镜像 |
| | 3-9 | `setup-cicd` 导入 `apollo-tech-common.properties` | 首次部署必做，导入 Apollo `tech.common` namespace |
| | 3-10 | `setup-cicd demo` | Demo 端到端验证 |
| | 3-12 | `setup-edge-nginx --env nonprod` | 非生产公网入口，可选 |
| **四 生产防线** | 4-1 ~ 4-5 | mysql/redis/mongodb/rabbitmq/consul --env prod | 生产中间件（与非生产物理隔离） |
| | **4-6** | `setup-apollo --env prod` | **一次拉起 3 容器**：MySQL_prod + Config + Admin（独立物理 MySQL） |
| | 4-7 | Portal 跨网段挂载 PRO 环境 | Apollo Portal 配置 `PRO` 环境 Meta Server 指向生产 Config |
| | 4-8 | `setup-k3s --env prod` | 生产 K3s 集群（物理孤岛） |
| | 4-9 | LGT prod（5 个 LGT skill --env prod） | 生产专属 LGT 栈 |
| | 4-10 | `setup-gitlab-runner --env prod` | 生产网段独立 Runner，tag `prod` |
| **五 外网放行** | 5-1 | `setup-edge-nginx --env prod` | 生产 DMZ 公网入口（必需），独立公网 IP / 独立机房 / 独立证书 |
| | 5-2 | 公网 DNS 解析 | 生产域名 A 记录指向生产 edge-nginx 公网 IP |

> 总计约 **42 次** `setup-*` 调用（详见架构蓝图附录 B.1）。

## 跨服务配置绑定

> 设置方→消费方对照。所有值默认使用域名（铁律二），跨节点连接清单详见 [references/configuration-reference.md](references/configuration-reference.md)。

| 配置项 | 设置方 | 消费方 | 默认值 | 说明 |
|-------|-------|-------|--------|------|
| `DNS_SERVER_IP` | setup-dns | 各机器 DNS / setup-k3s CoreDNS | dnsmasq 节点 IP | 唯一允许的 IP 跨服务变量；CoreDNS 转发目标 |
| `INFRA_NGINX_IP` | setup-dns `.env` | dnsmasq.conf `address=/.renew.com/` | infra-nginx 节点 IP | 泛解析兜底 IP |
| hosts.lan 37 条 | setup-dns | 所有 Pod / 微服务 | `CHANGE_ME_*_IP` | 集中维护直连域名 → IP 映射 |
| `GITLAB_HOST` / `GITLAB_SSH_PORT` | setup-gitlab | setup-infra-nginx | `gitlab.renew.com` / `2222` | infra-nginx HTTP 反代 + SSH stream 透传 |
| `NEXUS_HOST` / `NEXUS_DOCKER_PORT` | setup-nexus | setup-infra-nginx | `nexus.renew.com` / `8082` | infra-nginx HTTP 反代 + Docker Registry stream 透传 |
| `HARBOR_HOST` | setup-harbor | setup-infra-nginx + setup-k3s registries.yaml + Docker daemon.json | `harbor.renew.com` | 必须加入 `insecure-registries`（HTTP 模式） |
| `APOLLO_HOST` / `APOLLO_PROD_HOST` | setup-apollo | setup-infra-nginx | nonprod / prod 节点 IP | infra-nginx 反代 Portal `:8070` 与 Config `:8601-8605` |
| `apollo-config-{env}.renew.com` | setup-apollo + setup-infra-nginx | Spring Boot `apollo.meta`（app.sh 注入） | 泛解析→infra-nginx | 5 环境独立 Meta Server |
| `MYSQL_EXPORTER_HOST` / `REDIS_EXPORTER_HOST` / `MONGODB_EXPORTER_HOST` | setup-mysql / redis / mongodb（5 套） | setup-prometheus | `{svc}-{env}.renew.com` | Prometheus 静态抓取，relabel 注入 `env` 标签 |
| `RABBITMQ_HOST` | setup-rabbitmq（5 套）| setup-prometheus | `rabbitmq-{env}.renew.com:15692` | 内置 rabbitmq_prometheus 插件，无独立 exporter |
| `CONSUL_{ENV}_HOST` × 5 | setup-consul | setup-infra-nginx + setup-prometheus consul_sd | `consul-{env}.renew.com:8500` | Prometheus 通过 consul_sd 发现 Spring Boot；服务必须打 `metrics` tag |
| `TEMPO_HOST` | setup-tempo | setup-otel-collector / setup-grafana | `tempo-{nonprod\|prod}.renew.com` | OTel 推送 :14317 / Grafana 查询 :3200 |
| `LOKI_HOST` | setup-loki | setup-otel-collector / setup-grafana | `loki-{nonprod\|prod}.renew.com` | OTel 推送 :3100/otlp / Grafana 查询 :3100 |
| `PROMETHEUS_HOST` | setup-prometheus | setup-grafana / setup-tempo metrics_generator remote_write | `prometheus-{nonprod\|prod}.renew.com:9090` | 需开启 `--web.enable-remote-write-receiver` |
| `ALERTMANAGER_HOST` | setup-prometheus（同 compose）| setup-loki ruler / setup-prometheus alerting | `alertmanager-{nonprod\|prod}.renew.com:9093` | 跨节点告警推送 |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | setup-otel-collector | 业务 Pod（app.sh 注入） | `http://otel-{domainEnv}.renew.com:4317` | env→domainEnv 映射：dev/sit/fat/uat→nonprod；prod→prod |
| `OTEL_RESOURCE_ATTRIBUTES` | app.sh（setup-gitlab-runner）| 业务 Pod | `deployment.environment={env},service.namespace={env}` | LGT env 标签注入主通路 |
| `K3S_NONPROD_TRAEFIK_HOST` / `K3S_PROD_TRAEFIK_HOST` | setup-k3s | setup-infra-nginx + setup-edge-nginx | `k3s-{nonprod\|prod}.renew.com:8083` | 业务流量后端；必须用真实 IP，不可 127.0.0.1 |
| OTel Java Agent jar v2.26.1 | setup-gitlab-runner | 业务 Pod（K8s volumes 挂载） | `/opt/tech-stack/cicd/opentelemetry-javaagent.jar` | 跨 JDK 8~21 通用，方案 B 兜底 |

## 版本兼容矩阵

> 业务框架 → 基础设施版本。详见 architecture-blueprint.md 附录 A。

| 业务框架 | 版本 | 对应基础设施 |
|---------|------|------------|
| JDK | 21（主力）/ 11（兜底） | 21 用于 Spring Boot 3.x 方案 A；11 用于 Spring Boot 2.x 方案 B |
| Spring Boot | **3.5.x（主力）** / 2.7.x（兜底） | 3.x 用 Micrometer + OTel Bridge；2.x 用 OTel Java Agent |
| Spring Cloud | 2025.0.0 (Northfields) | Consul 1.20 |
| Apollo Client | 2.4.0 | Apollo 2.5.0 |
| Redisson | 4.3.0 | Redis 8.0 |
| Spring AMQP | 4.x | RabbitMQ 4.0 |
| Spring Data MongoDB | 4.4.x | MongoDB 8.0 |
| Micrometer Tracing | 1.4.x | 方案 A 链路桥接，Spring Boot 3.x 内置 |
| Micrometer Prometheus | — | 方案 A/B 共用，产出 `/actuator/prometheus` |
| OpenTelemetry SDK (Bridge) | 1.45+ | 方案 A 配合 Micrometer Tracing 导出 OTLP |
| OpenTelemetry Java Agent | 2.11.x+（实际 v2.26.1） | 方案 B 字节码注入，JDK 8+ 兼容 |

## 架构决策记录

| 决策 | 结论 |
|------|------|
| K3s + Docker Compose 混合架构 | 业务应用迁移到 K3s（自动扩缩容 / 故障自愈），中间件 / LGT 栈 / Apollo 全部留在 K3s 外部 Docker Compose（运维边界清晰） |
| 三大逻辑域分离 | 全局共享层 1 套（GitLab/Nexus/Harbor/DNS/infra-nginx）+ 非生产域 1 套（4 环境共用）+ 生产域 1 套（物理孤岛） |
| infra-nginx 预配置 | DNS 后立即部署，一次性配置全部反代规则（含尚未部署的服务）；上游不可达返回 502，不影响 nginx 自身运行 |
| Apollo 一次到位合并部署 | nonprod 一个 Compose 拉起 10 容器（MySQL+Portal+4×Config/Admin）；prod 一个 Compose 拉起 3 容器；避免 MySQL/应用拆分两步部署的协调成本 |
| Apollo MySQL 内置管理 | 由 setup-apollo 自带，与业务 MySQL（setup-mysql ×5）完全分离 |
| LGT env 标签隔离 | nonprod 1 套 LGT 通过 `OTEL_RESOURCE_ATTRIBUTES=deployment.environment={env}`（app.sh Pod 级注入）+ Prometheus `relabel_configs` 在抓取端附加 `env` 标签实现 4 环境逻辑隔离 |
| 双方案 OTel 接入 | 方案 A（Micrometer + OTel Bridge，SB 3.x 主力）/ 方案 B（OTel Java Agent，SB 2.x 兜底，jar 由 setup-gitlab-runner 统一管理 + volumes 挂载） |
| Metrics 与 Traces/Logs 通路解耦 | Metrics 由 Prometheus 拉取 `/actuator/prometheus`（强制 `OTEL_METRICS_EXPORTER=none`）；Traces/Logs 由 OTel SDK/Agent 推送到 Collector |
| edge-nginx 双 DMZ 实例 | nonprod / prod 各独立公网 IP / 独立机房 / 独立 SSL 证书；按 `--env` 切换 K3s 后端 |
| CoreDNS 转发 .renew.com | K3s CoreDNS 用 `coredns-custom` ConfigMap 配置 `forward .renew.com ${DNS_SERVER_IP}`，Pod 通过域名直连基础设施 |
| 域名四层结构 | 全局唯一 / 域级共用 / 非生产独有 / 环境级；直连写 hosts.lan，UI 加 `-ui` 后缀走泛解析→infra-nginx |

## 项目约定

- **偏向谨慎而非速度**：基础设施部署是高副作用操作（远程 SSH / 起容器 / 改防火墙 / 删数据），任何破坏性 / 跨机器 / 跨环境的动作前主动停下确认。简单可逆任务自行判断
- 每个 skill 结构：`SKILL.md` + `actions/` + `references/`（含 `pitfalls.md`）+ `README.md` + `install.sh`
- 部署目录：`/opt/tech-stack/<service>/` 或多环境 `/opt/tech-stack/<service>-{env}/`
- 容器命名：`tech-<service>` 或多环境 `tech-<service>-{env}`
- 所有跨服务通信通过 `*.renew.com` 域名寻址；各服务 `.env` 中 `*_HOST` 默认使用域名
- 所有密码使用 `CHANGE_ME_*` 占位符；按 `{服务缩写}{角色}_{16位随机}` 规则生成（如 `MysRoot_aB3kP7mN9xQ2wE5r`）
- `--env` 参数支持按蓝图附录 B.2 的 6 类契约实现（A 环境级 / B 域级 / C 全局唯一 / D Apollo 合并 / E 业务接入指导）
- **正向描述原则**：所有 skill 文件和 summary 文件只写"现在该怎么做"。禁止写演进史、新旧对比、复查痕迹、修复编年史。旧做法本身错的就直接删除
- **踩坑沉淀**：部署 / 运维过程中的问题、踩坑教训、决策原因、历史脉络，统一写入对应 skill 的 `references/pitfalls.md`，不污染 SKILL.md / README / actions
- 提问偏好：使用 AskUserQuestion 问卷形式向用户提问，不用纯文本列表
- 干净服务器假设：`setup-*` skill 遇到端口 / 资源冲突只检测和通知，不做系统级修改
- 必要的英文参数（函数参数、配置项、枚举值含义不直观时）增加中文注释；变量名已清晰的不加

## 文档索引

| 主题 | 路径 | 何时读取 |
|------|------|---------|
| 架构蓝图（最终权威） | [architecture-blueprint.md](architecture-blueprint.md) | 任何架构决策前必读全文 |
| 可观测性 env 标签隔离 | [architecture-blueprint.md](architecture-blueprint.md) + 附属拆分文档 | LGT 栈 env 标签实现细节、双方案对比 |
| references 索引 | [references/README.md](references/README.md) | 文档导航、分层架构图 |
| 网络架构 | [references/network-architecture.md](references/network-architecture.md) | 双入口流量路径、DNS 解析机制、四层域名规范 |
| 配置参考 | [references/configuration-reference.md](references/configuration-reference.md) | 跨节点连接清单、环境变量全表 |
| 部署原则 | [references/deployment-principles.md](references/deployment-principles.md) | 核心原则、Docker / 内核参数 / Exporter 用户 / 密码生成规则 / 版本兼容踩坑 |
| 可观测性数据流 | [references/observability-pipeline.md](references/observability-pipeline.md) | OTel → Tempo/Loki/Prometheus 数据流；双方案接入；env 标签注入 |
| 请求生命周期 | [references/request-lifecycle.md](references/request-lifecycle.md) | 端到端案例（含多环境），新人入门 |
| 资源规划 | [references/resource-planning.md](references/resource-planning.md) | 资源估算、高可用演进路径、备份策略、部署模式说明 |
| 部署指南模板库 | [references/deployment-guide/](references/deployment-guide/) | 五阶段 21 个 task 模板，按需生成 deployment-plan |
| Spring Boot 接入 | [setup-cicd/actions/integrate.md](setup-cicd/actions/integrate.md) | 业务服务接入全套基础设施（双方案 + 关闭 OTel 三套示例） |
| Spring Boot 部署规范 | [setup-gitlab-runner/references/app-sh-spec.md](setup-gitlab-runner/references/app-sh-spec.md) | app.sh 生成的 K8s 资源结构（Deployment/HPA/PDB/Service/Ingress/PVC） |

## 文档同步规范

> 新增 / 删除 / 修改服务时按下表检查，避免文档间漂移。

| 触发动作 | 同步检查范围 |
|---------|------------|
| 新增 / 删除服务 | 本文件「服务注册表」表 → README.md「服务组成」表 → references/README.md 分层图 → architecture-blueprint.md 附录 A/B |
| 修改部署顺序 / 跨服务依赖 | 本文件「部署顺序（五阶段）」 + 「跨服务配置绑定」 → references/deployment-principles.md → architecture-blueprint.md 第五部分 |
| 修改版本号 | 本文件「版本兼容矩阵」 → architecture-blueprint.md 附录 A → 对应 skill 的 SKILL.md / `.env.example` |
| 调整 `--env` 契约 | 本文件「多环境隔离策略」 → architecture-blueprint.md 附录 B.2 → 对应 skill `actions/start.md` |
| 新增安全要点 | README.md「安全加固检查清单」 → 对应 skill 的 README.md / pitfalls.md
