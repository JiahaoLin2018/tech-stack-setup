# FinTech 级纯粹隔离微服务架构与投产方案

> **文档定位**：基于 `tech-stack-setup` 工程体系的企业级多环境隔离方案。本文档定义了从全局基础设施到生产投产的完整架构蓝图，覆盖组件分类、隔离策略、可观测性打标、安全加固与严格的部署顺序。
>
> **核心理念**：所有 `setup-*` 基础服务与中间件采用独立部署（物理机 / 虚拟机 / Docker Compose），`setup-k3s` 仅作为纯粹的"无状态业务应用运行底座"。

---

## 目录

- [第一部分：整体架构与组件拓扑](#第一部分整体架构与组件拓扑)
  - [1. 架构分层总览](#1-架构分层总览)
  - [2. 全局内网核心区](#2-全局内网核心区-global-internal-zone)
  - [3. 非生产环境域](#3-非生产环境域-non-production-domain)
  - [4. 生产环境域与外网入口](#4-生产环境域与外网入口-production--dmz-zone)
- [第二部分：Apollo 多环境配置中心架构](#第二部分apollo-多环境配置中心架构)
- [第三部分：域名寻址与网络架构](#第三部分域名寻址与网络架构)
- [第四部分：安全加固基线](#第四部分安全加固基线)
- [第五部分：严格部署与投产顺序](#第五部分严格部署与投产顺序)
- [附录 A：技术栈版本清单](#附录-a技术栈版本清单)
- [附录 B：setup-* Skill 与组件映射表](#附录-bsetup--skill-与组件映射表)

---

## 第一部分：整体架构与组件拓扑

### 1. 架构分层总览

整个基础设施划分为 **一个全局共享层** + **两大逻辑域** + **两条外网安全边界**，遵循"计算/监控资源非生产可合用，数据/状态组件各环境彻底隔离"的核心策略。

> **术语约定**：
>
> - **全局共享层 (Global Internal Zone)** = 跨域共享的研发资产与内网基座（DNS / infra-nginx / GitLab / Nexus / Harbor），**全局唯一**一套，不属于任何一个域。
> - **域 (Zone)** = 物理 / 网络隔离单元，共两个：**Non-Prod**（非生产域）和 **Prod**（生产域）。两域之间在硬件、网络、数据上零交集。
> - **环境 (Env)** = 业务阶段，共五个：Dev / SIT / FAT / UAT（位于非生产域）、Prod（位于生产域）。
> - 非生产域内承载 4 个环境，生产域内仅承载 1 个环境。下文所有"跨环境隔离"讨论都发生在**非生产域内部**；非生产与生产之间是**跨域物理隔离**。

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       FinTech 级纯粹隔离架构总览                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │               全局内网核心区 (Global Internal Zone)                  │   │
│  │                                                                     │   │
│  │  网络基座:    setup-dns · setup-infra-nginx                         │   │
│  │  研发资产:    setup-gitlab · setup-nexus · setup-harbor             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                               │                                            │
│         ┌─────────────────────┴──────────────────────┐                    │
│         ▼                                            ▼                    │
│  ┌──────────────────────────────┐  ┌──────────────────────────────────┐  │
│  │  非生产环境域                 │  │  生产环境域                       │  │
│  │  (Non-Prod Domain)           │  │  (Prod Domain)                   │  │
│  │                              │  │                                  │  │
│  │  共用底座:                   │  │  物理孤岛:                       │  │
│  │    setup-k3s (非生产集群)    │  │    setup-k3s (生产专属集群)       │  │
│  │    gitlab-runner (non-prod)  │  │    gitlab-runner (prod)          │  │
│  │                              │  │                                  │  │
│  │  可观测性 (LGT 栈):          │  │  可观测性 (LGT 栈):              │  │
│  │    otel-collector (nonprod)  │  │    otel-collector (prod)         │  │
│  │    loki / tempo / prometheus │  │    loki / tempo / prometheus     │  │
│  │    grafana (nonprod 共用)    │  │    grafana (prod 专属)           │  │
│  │                              │  │                                  │  │
│  │  配置中心:                   │  │  配置中心:                       │  │
│  │    Apollo Portal + MySQL     │  │    Apollo Config/Admin (prod)    │  │
│  │    Apollo Config/Admin ×4    │  │    Apollo 专用 MySQL (prod)      │  │
│  │    (dev/sit/fat/uat)         │  │                                  │  │
│  │                              │  │                                  │  │
│  │  环境级独立 ×4:              │  │  生产级独立:                     │  │
│  │    Dev / SIT / FAT / UAT     │  │    Prod                         │  │
│  │    每环境独立中间件 + 配置    │  │    独立中间件 + 配置              │  │
│  └──────────────┬───────────────┘  └─────────────────┬────────────────┘  │
│                 │                                    │                   │
│                 ▼                                    ▼                   │
│      ┌──────────────────────┐             ┌──────────────────────┐       │
│      │  DMZ 外网边界(非生产) │             │  DMZ 外网边界(生产)   │       │
│      │  setup-edge-nginx    │             │  setup-edge-nginx    │       │
│      │  [独立公网IP/隔离机房]│             │  [独立公网IP/物理孤岛]│       │
│      └──────────────────────┘             └──────────────────────┘       │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 1.1 隔离粒度速查表

按"部署实例数量"归纳全部 `setup-*` 组件，一目了然哪些是全局唯一、哪些按域切分、哪些按环境彻底独立：

| 隔离粒度 | 实例数 | 组件 | 说明 |
|---|---|---|---|
| **全局唯一** | 1 套 | `setup-dns` · `setup-infra-nginx` · `setup-gitlab` · `setup-nexus` · `setup-harbor` | 全公司研发资产与内网路由基座，非生产域与生产域共享同一套（位于全局共享层） |
| **域级共用**（非生产 1 套 + 生产 1 套） | 2 套 | `setup-k3s` · `setup-otel-collector` · `setup-loki` · `setup-tempo` · `setup-prometheus` · `setup-grafana` · `setup-gitlab-runner` · `setup-apollo` · `setup-edge-nginx` | 非生产域内 4 环境共用一套，生产域独立一套（物理孤岛）。LGT 栈通过 `env` 标签做逻辑隔离，详见 `observability-env-isolation.md` |
| **环境级彻底独立** | 5 套 | `setup-mysql` · `setup-redis` · `setup-mongodb` · `setup-rabbitmq` · `setup-consul` | Dev / SIT / FAT / UAT / Prod 各自独立实例，无任何数据交集 |

> 各 Skill 的部署次数、`--env` 参数契约详见 [附录 B](#附录-bsetup--skill-与组件映射表)。

#### 1.2 infra-nginx 跨域反代职责（生产域无需独立 infra-nginx）

全局共享层中的 infra-nginx 不仅反代非生产 UI 与 Apollo Portal，还**跨网段反代生产域的 Web UI**（如 `grafana-prod-ui.renew.com`、`prometheus-prod-ui.renew.com`、`alertmanager-prod-ui.renew.com`）以及生产 Apollo Config Service（`apollo-config-prod.renew.com`）。内网用户连入即可统一访问全部环境的管理入口与配置中心，无需在生产域内重复部署 Web 反代。

因此 **生产域内部不部署 infra-nginx**：

- **公网业务流量**由 edge-nginx (prod) 在 DMZ 区承担（独立公网 IP / 独立证书 / 物理孤岛）
- **生产 DNS 解析**由独立的生产 DNS 服务承担（公有云 PrivateZone 或自建 dnsmasq），仅需提供生产域内 Pod 直连基础设施所需的域名解析能力
- **生产 Web UI 与 Apollo Config**由全局共享层 infra-nginx 跨网段反代

> 上云后生产 UI 仍由内网 infra-nginx 跨域反代不变，跨域 VPN 故障期接受运维短期失能（业务可用性不受影响）；详见 [cloud-migration-reference.md §4.3](cloud-migration-reference.md#43-反代层保持内网-infra-nginx-跨域反代生产-ui不部署-prod-infra-nginx)。

---

### 2. 全局内网核心区 (Global Internal Zone)

负责企业级研发资产管理与内网路由调度。此区域的服务是**全局唯一**的，跨所有环境共享。

| **分类** | **服务组件** | **Skill** | **部署位置** | **核心职责** |
|----------|-------------|-----------|-------------|-------------|
| 网络基座 | dnsmasq | `setup-dns` | 全局独立节点 | 内部统一 DNS 解析中心，所有 `*.renew.com` 域名的权威来源 |
| 网络基座 | infra-nginx | `setup-infra-nginx` | 内网独立节点 | 唯一内网入口，负责内部系统域名反代、跨环境路由分发及内网准入控制 |
| 研发资产 | GitLab EE | `setup-gitlab` | 全局独立节点 | 统一代码托管 + CI/CD 管理平台 |
| 研发资产 | Nexus OSS | `setup-nexus` | 全局独立节点 | Maven/NPM 依赖包私服，加速编译构建 |
| 研发资产 | Harbor | `setup-harbor` | 全局独立节点 | 统一 Docker 容器镜像仓库 |

---

### 3. 非生产环境域 (Non-Production Domain)

**适用环境**：`Dev` (开发)、`SIT` (系统测试)、`FAT` (功能/验收测试)、`UAT` (用户验收测试)

**核心策略**：底层计算集群与监控平台共用，但**核心中间件与业务数据 100% 物理/实例隔离**。

> **重要原则**：所有中间件（MySQL、Redis、MongoDB、RabbitMQ、Consul）均在 K3s **外部**以独立 Docker Compose 方式部署，与 K3s 无关。K3s 仅作为纯粹的无状态业务应用运行底座，只负责微服务代码的编排和运行。

#### 3.1 共用基础设施 (Shared Infrastructure)

| **组件** | **Skill** | **部署方式** | **隔离策略** |
|----------|-----------|-------------|-------------|
| K3s 集群 (非生产) | `setup-k3s` | 独立物理机/虚拟机 | 纯粹的业务应用运行底座，通过 K8s Namespace (`dev`, `sit`, `fat`, `uat`) 实现应用进程与网络边界的逻辑隔离 |
| Loki (日志) | `setup-loki` | K3s **外部**独立服务器 (Docker Compose) | 通过 `env={namespace}` 标签区分各环境日志 |
| Prometheus (指标) | `setup-prometheus` | K3s **外部**独立服务器 (Docker Compose) | 通过 `relabel_configs` 映射 namespace 为 `env` 标签 |
| Tempo (链路) | `setup-tempo` | K3s **外部**独立服务器 (Docker Compose) | 通过 OTel Collector 注入 `deployment.environment` 属性 |
| OTel Collector | `setup-otel-collector` | K3s **外部**独立服务器 (Docker Compose) | 统一遥测数据网关，为数据附加环境标签后分发 |
| Grafana | `setup-grafana` | K3s **外部**独立服务器 (Docker Compose) | 统一可视化看板，通过标签过滤不同环境数据 |
| GitLab Runner (non-prod) | `setup-gitlab-runner` | K3s **外部**独立节点 (Docker Compose) | 一站式部署 Runner 容器 + CI Job 执行环境（app.sh、kubeconfig、静态工具、基础镜像），配置 `tag: non-prod` |

#### 3.2 环境级独立组件 (Environment-Specific Instances)

为 `Dev`、`SIT`、`FAT`、`UAT` **各自部署完全独立的一套**中间件，**全部在 K3s 外部以 Docker Compose 独立部署**：

| **组件** | **Skill** | **部署方式** | **Dev 实例** | **SIT 实例** | **FAT 实例** | **UAT 实例** |
|----------|-----------|-------------|-------------|-------------|-------------|-------------|
| MySQL (业务) | `setup-mysql` | K3s 外部独立 Docker Compose | ✅ 独立 | ✅ 独立 | ✅ 独立 | ✅ 独立 |
| Redis | `setup-redis` | K3s 外部独立 Docker Compose | ✅ 独立 | ✅ 独立 | ✅ 独立 | ✅ 独立 |
| MongoDB | `setup-mongodb` | K3s 外部独立 Docker Compose | ✅ 独立 | ✅ 独立 | ✅ 独立 | ✅ 独立 |
| RabbitMQ | `setup-rabbitmq` | K3s 外部独立 Docker Compose | ✅ 独立 | ✅ 独立 | ✅ 独立 | ✅ 独立 |
| Consul | `setup-consul` | K3s 外部独立 Docker Compose | ✅ 独立 | ✅ 独立 | ✅ 独立 | ✅ 独立 |

> **隔离保证**：
>
> - **中间件与 K3s 完全解耦**：所有中间件以独立 Docker Compose 部署在 K3s 外部的物理机/虚拟机上，K3s 中的业务 Pod 通过 DNS 域名直连中间件（如 `mysql-dev.renew.com:3306`）
> - 每环境的业务 MySQL 是**完全独立的**物理/虚拟实例，与 Apollo 专用 MySQL 无关
> - Consul 各环境独立实例，避免服务注册信息交叉污染

#### 3.3 Apollo 配置体系 (非生产)

Apollo 配置中心采用 **一次到位合并部署** 策略：Portal、Apollo 专用 MySQL、四环境 Config/Admin Service 全部由 `setup-apollo --env nonprod` 一个命令拉起（共 10 个容器），避免将 MySQL 与应用拆成两步部署带来的协调成本。

| **组件** | **Skill** | **部署方式** | **说明** |
|----------|-----------|-------------|------|
| Apollo 专用 MySQL (非生产) | `setup-apollo --env nonprod` 内置 | 同一 Docker Compose 编排 | 存放 `ApolloPortalDB` + 各测试环境的 `ApolloConfigDB_{env}`，与业务 MySQL（`setup-mysql`）完全独立 |
| Apollo Portal | `setup-apollo --env nonprod` 内置 | 同一 Docker Compose 编排 | 统一配置中心前端管理门户 (:8070)，管理所有环境的配置 |
| Apollo Config Service (×4) | `setup-apollo --env nonprod` 内置 | 同一 Docker Compose 编排 | 各环境独立容器：Dev :8601 / SIT :8602 / FAT :8603 / UAT :8604 |
| Apollo Admin Service (×4) | `setup-apollo --env nonprod` 内置 | 同一 Docker Compose 编排 | 各环境独立容器：Dev :8611 / SIT :8612 / FAT :8613 / UAT :8614 |

> **关键设计**：Apollo 的数据库采用"物理实例隔离 + 逻辑库分离"的混合策略：
>
> - 非生产环境的 Apollo 配置库（`ApolloConfigDB_dev/sit/fat/uat`）共用一个 Apollo 专用 MySQL 实例，但各自独立 Schema
> - 生产环境的 Apollo 配置库（`ApolloConfigDB_prod`）使用**完全独立**的生产 Apollo 专用 MySQL 实例（见 4.3 生产 Apollo 配置体系）
> - Apollo Config + Admin Service 各环境独立容器，连接 Apollo 专用 MySQL (非生产) 中**各自对应的独立 Schema**
> - **Apollo MySQL 由 `setup-apollo` 内置管理**，不通过 `setup-mysql` 单独部署；`setup-mysql` 仅负责业务 MySQL ×5 套

#### 3.4 外网边界 (非生产 DMZ)

承接 dev/sit/fat/uat 四套环境的外网业务流量入口。

| **组件** | **Skill** | **部署位置** | **职责** |
|----------|-----------|-------------|---------|
| edge-nginx (非生产) | `setup-edge-nginx --env nonprod` | 非生产域 DMZ 独立机房 | 拥有独立公网 IP，将 `{project}.{env}.web/api.renew.com` 路由至 K3s 非生产集群 |

> **访问控制**：支持公开访问或 IP 白名单（按域名精确配置）。仅支持 HTTPS，HTTP 自动 301 重定向。

---

### 4. 生产环境域与外网入口 (Production & DMZ Zone)

**适用环境**：`Prod` (生产)

**核心策略**：真正的"物理孤岛"，与非生产环境**无任何硬件、网络或数据交集**。

#### 4.1 生产独立基础设施

| **组件** | **Skill** | **部署方式** | **关键要求** |
|----------|-----------|-------------|-------------|
| K3s 集群 (生产) | `setup-k3s` | 全新物理机 / 隔离 VPC | 纯净生产计算底座，只运行生产微服务代码 |
| Loki (生产) | `setup-loki` | 生产专属独立服务器 | 确保存储与查询不受测试环境海量日志干扰 |
| Prometheus (生产) | `setup-prometheus` | 生产专属独立服务器 | 专属生产监控指标采集 |
| Tempo (生产) | `setup-tempo` | 生产专属独立服务器 | 专属生产链路追踪 |
| OTel Collector (生产) | `setup-otel-collector` | 生产专属独立服务器 | 生产遥测数据网关 |
| Grafana (生产) | `setup-grafana` | 生产专属独立服务器 | 生产专属监控看板 |
| GitLab Runner (prod) | `setup-gitlab-runner` | 生产网段独立节点 | 一站式部署 Runner 容器 + CI Job 执行环境，配置 `tag: prod`，确保生产编译和发布仅在安全网络域内执行 |

#### 4.2 生产独立中间件（物理隔离）

初期与测试环境保持一致，采用**单实例 Docker Compose** 部署，确保部署流程统一、快速交付。后续可根据业务量级逐步演进为高可用架构。

| **组件** | **Skill** | **部署方式** | **部署要求** |
|----------|-----------|-------------|-------------|
| MySQL (Prod 业务) | `setup-mysql` | K3s 外部独立 Docker Compose | 生产专属独立实例，与非生产完全物理隔离 |
| Redis (Prod) | `setup-redis` | K3s 外部独立 Docker Compose | 生产专属独立实例 |
| MongoDB (Prod) | `setup-mongodb` | K3s 外部独立 Docker Compose | 生产专属独立实例 |
| RabbitMQ (Prod) | `setup-rabbitmq` | K3s 外部独立 Docker Compose | 生产专属独立实例 |
| Consul (Prod) | `setup-consul` | K3s 外部独立 Docker Compose | 生产专属独立实例 |

> **后续高可用演进建议**（当前暂不实施，待业务量级增长后按需升级）：
>
> | 组件 | 高可用方案 | 收益 |
> |------|-----------|------|
> | MySQL | 主从架构 + `innodb_buffer_pool_size = 物理内存 70%` | 读写分离、故障自动切换 |
> | Redis | Sentinel 哨兵模式 或 Cluster 集群模式 | 自动故障转移、水平扩展 |
> | MongoDB | 副本集 (Replica Set) | 数据冗余、自动选主 |
> | RabbitMQ | 集群模式 + Quorum Queue | 消息持久化、节点容灾 |
> | Consul | 3 节点集群 + ACL 开启 | Raft 共识、安全准入 |

#### 4.3 生产 Apollo 配置体系

生产 Apollo 同样采用 **一次到位合并部署**：由 `setup-apollo --env prod` 一个命令在生产网段拉起生产 Apollo 专用 MySQL + 生产 Config + 生产 Admin（共 3 个容器）。

| **组件** | **Skill** | **部署方式** | **说明** |
|----------|-----------|-------------|------|
| Apollo 专用 MySQL (生产) | `setup-apollo --env prod` 内置 | 同一 Docker Compose 编排 | 生产环境专属独立数据库实例，存放 `ApolloConfigDB_prod`，与非生产 Apollo MySQL 完全物理隔离 |
| Apollo Config Service (Prod) | `setup-apollo --env prod` 内置 | 同一 Docker Compose 编排 | 生产专属 Config Service (:8605)，连接生产 Apollo 专用 MySQL |
| Apollo Admin Service (Prod) | `setup-apollo --env prod` 内置 | 同一 Docker Compose 编排 | 生产专属 Admin Service (:8615) |

> **跨网段挂载**：在非生产域的 Apollo Portal 中配置生产环境的 Meta Server 路由（`PRO` 环境指向生产 Config Service 地址），使 Portal 可统一管理生产配置，但**后端数据完全分离**。

#### 4.4 外网边界 (生产 DMZ)

| **组件** | **Skill** | **部署位置** | **职责** |
|----------|-----------|-------------|---------|
| edge-nginx (生产) | `setup-edge-nginx --env prod` | 生产域 DMZ 独立机房 | 拥有专属公网 IP，将 `{project}.prod.web/api.renew.com` 路由至 K3s 生产集群，与非生产网关物理隔离 |

> **访问控制**：支持公开访问或 IP 白名单（按域名精确配置）。仅支持 HTTPS，HTTP 自动 301 重定向。

---

## 第二部分：Apollo 多环境配置中心架构

### 整体架构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Apollo 配置中心 — 全局架构                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                 Apollo Portal (全局唯一)                             │   │
│  │                 :8070 统一配置管理 UI                                │   │
│  │                                                                     │   │
│  │  apollo.portal.envs = dev,sit,fat,uat,pro                          │   │
│  │  apollo.portal.meta.servers = {                                     │   │
│  │    "DEV": "http://apollo-config-dev:8080",                         │   │
│  │    "SIT": "http://apollo-config-sit:8080",                         │   │
│  │    "FAT": "http://apollo-config-fat:8080",                         │   │
│  │    "UAT": "http://apollo-config-uat:8080",                         │   │
│  │    "PRO": "http://apollo-config-prod.renew.com:8080"  ← 跨网段     │   │
│  │  }                                                                  │   │
│  └──────────────────────────────┬──────────────────────────────────────┘   │
│                                 │                                          │
│         ┌───────────────────────┴───────────────────────────┐              │
│         ▼                                                   ▼              │
│  ┌──────────────────────────────┐  ┌───────────────────────────────────┐  │
│  │  Apollo 专用 MySQL (非生产)  │  │  Apollo 专用 MySQL (生产)         │  │
│  │                              │  │                                   │  │
│  │  Schema:                     │  │  Schema:                          │  │
│  │    ApolloPortalDB            │  │    ApolloConfigDB_prod            │  │
│  │    ApolloConfigDB_dev        │  │                                   │  │
│  │    ApolloConfigDB_sit        │  │  ★ 完全独立物理实例               │  │
│  │    ApolloConfigDB_fat        │  │  ★ 生产网段部署                   │  │
│  │    ApolloConfigDB_uat        │  │                                   │  │
│  └──────────────────────────────┘  └───────────────────────────────────┘  │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    Config + Admin Service 分布                       │   │
│  │                                                                     │   │
│  │  非生产区（各环境独立实例）:                                         │   │
│  │    DEV:  Config :8601 + Admin :8611 → ApolloConfigDB_dev            │   │
│  │    SIT:  Config :8602 + Admin :8612 → ApolloConfigDB_sit            │   │
│  │    FAT:  Config :8603 + Admin :8613 → ApolloConfigDB_fat            │   │
│  │    UAT:  Config :8604 + Admin :8614 → ApolloConfigDB_uat            │   │
│  │                                                                     │   │
│  │  生产区（独立实例）:                                                 │   │
│  │    PROD: Config :8605 + Admin :8615 → ApolloConfigDB_prod           │   │
│  │          ★ 部署在生产网段，连接生产专用 MySQL                        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Spring Boot 接入

| 环境 | `apollo.meta` | 来源 |
|------|---------------|------|
| dev | `http://apollo-config-dev.renew.com` | infra-nginx 代理 |
| sit | `http://apollo-config-sit.renew.com` | infra-nginx 代理 |
| fat | `http://apollo-config-fat.renew.com` | infra-nginx 代理 |
| uat | `http://apollo-config-uat.renew.com` | infra-nginx 代理 |
| prod | `http://apollo-config-prod.renew.com` | 生产网段直连 |

> CI/CD 部署时 `app.sh` 自动注入 `-Dapollo.meta=http://apollo-config-${env}.renew.com`，无需手动配置。

### Apollo 环境命名约定

| 环境 | Apollo 内置名 | 容器后缀 | 数据库 Schema | 说明 |
|------|-------------|---------|-------------|------|
| 开发 | DEV | dev | ApolloConfigDB_dev | — |
| 系统测试 | SIT | sit | ApolloConfigDB_sit | Apollo 2.5.0 中 FWS 不可用（硬编码映射 FWS→FAT），改用 SIT |
| 功能测试 | FAT | fat | ApolloConfigDB_fat | — |
| 验收测试 | UAT | uat | ApolloConfigDB_uat | — |
| 生产 | **PRO** | **prod** | ApolloConfigDB_prod | Portal 配置中 JSON key 为 `PRO`，容器名为 `apollo-config-prod` |

---

## 第三部分：域名寻址与网络架构

### 域名分类体系

所有内部服务统一使用 `*.renew.com` 域名进行通信。根据服务的部署范围，域名命名分为以下四层：

| **域名层级** | **命名规范** | **示例** | **解析方式** | **适用组件** |
|-------------|---------|---------|-------------|-------------|
| ① 全局唯一 | `{service}.renew.com` | `gitlab.renew.com`、`nexus.renew.com`、`harbor.renew.com`、`dns.renew.com` | 泛解析 → infra-nginx | 仅一套，跨所有环境共享：DNS、infra-nginx、GitLab、Nexus、Harbor |
| ② 域级直连数据端口 | `{service}-nonprod/prod.renew.com` | `otel-nonprod.renew.com`、`loki-nonprod.renew.com`、`prometheus-nonprod.renew.com`、`alertmanager-nonprod.renew.com` | **hosts.lan** 精确匹配 | Pod / 服务直连数据端口，非生产/生产各一套：OTel Collector、Loki、Tempo、Prometheus、Alertmanager |
| ② 域级共用 UI | `{service}-nonprod/prod-ui.renew.com` | `grafana-nonprod-ui.renew.com`、`prometheus-nonprod-ui.renew.com`、`alertmanager-nonprod-ui.renew.com` | 泛解析 → infra-nginx | 浏览器访问的管理 UI，非生产/生产各一套：Grafana、Prometheus UI、Alertmanager |
| ③ 非生产域独有 | `{service}.renew.com` | `apollo.renew.com` | 泛解析 → infra-nginx | 仅非生产域一套：Apollo Portal |
| ④ 环境级直连 | `{service}-{env}.renew.com` | `mysql-dev.renew.com`、`consul-fat.renew.com`、`rabbitmq-uat.renew.com` | **hosts.lan** 精确匹配 | Pod 直连中间件服务端口：MySQL、Redis、MongoDB、RabbitMQ、Consul |
| ④ 环境级 Web UI | `{service}-{env}-ui.renew.com` | `consul-dev-ui.renew.com`、`rabbitmq-uat-ui.renew.com` | 泛解析 → infra-nginx | 浏览器访问中间件管理 UI：Consul UI、RabbitMQ UI 等 |
| ④ Apollo Config | `apollo-config-{env}.renew.com` | `apollo-config-fat.renew.com` | 泛解析 → infra-nginx | 每环境独立的 Apollo Config Service |
| ④ 业务应用 | `{project}.{env}.{type}.renew.com` | `zoro.fat.web.renew.com`、`gateway.prod.api.renew.com` | edge-nginx / infra-nginx → K3s | K3s 中的微服务，`type` 为 `web` 或 `api` |

> **速查口诀**：解析方式列标注 **hosts.lan** 的即需要写入 hosts.lan；其余均为泛解析 → infra-nginx 代理。

> **直连 vs Web UI 域名区分**（-ui 后缀普遍适用）：
>
> 凡是有独立"数据端口"（Pod 直连）和"管理 UI"（浏览器访问）的服务，两者域名必须区分：
>
> - **直连数据端口**：写入 hosts.lan 精确匹配，如 `consul-dev.renew.com:8500`、`otel-nonprod.renew.com:4317`
> - **管理 Web UI**：加 `-ui` 后缀，泛解析 → infra-nginx 代理，如 `consul-dev-ui.renew.com`、`grafana-nonprod-ui.renew.com`
>
> **-ui 后缀适用于所有层级**（环境级 ④ 和域级共用 ②）。Prometheus 同时有直连数据端口（`prometheus-nonprod.renew.com:9090`，hosts.lan）和 UI（`prometheus-nonprod-ui.renew.com`，代理）。

### 多环境域名规划

在多环境隔离架构中，所有服务的域名按上述规则进行规划：

```
# ================================================================
# hosts.lan — 只写 Pod/微服务需要直接 TCP 连接的域名
#
# 不写入 hosts.lan 的域名（全部由泛解析 → infra-nginx 代理处理）：
#   ① 全局唯一：gitlab / nexus / harbor / dns
#   ② 域级共用 UI：grafana-nonprod-ui / prometheus-nonprod-ui / alertmanager-nonprod-ui 等
#   ③ 非生产独有：apollo.renew.com
#   ④ 环境级 Web UI：consul-{env}-ui / rabbitmq-{env}-ui 等
#   ④ Apollo Config：apollo-config-{env}.renew.com
#   业务应用：*.{env}.web/api.renew.com
# ================================================================

# ============ ② 域级直连数据端口 ============
# 规范：{service}-nonprod/prod.renew.com，Pod 直连数据端口
# 非生产域（OTel/Loki/Tempo：OTLP 推送直连；Prometheus：指标推送/查询直连）
192.168.x.x   otel-nonprod.renew.com        # Pod 直连 :4317/:4318 (OTLP)
192.168.x.x   loki-nonprod.renew.com        # OTel Collector 推送 :3100
192.168.x.x   tempo-nonprod.renew.com       # OTel Collector 推送 :14317 gRPC / :14318 HTTP，Grafana 查询 :3200
192.168.x.x   prometheus-nonprod.renew.com  # 指标推送/Grafana 查询 :9090
192.168.x.x   alertmanager-nonprod.renew.com # Prometheus alerting 推送 / Loki ruler 推送 :9093
192.168.x.x   k3s-nonprod.renew.com         # edge-nginx/infra-nginx 转发目标 :8083
# 生产域（独立物理隔离）
10.0.x.x      otel-prod.renew.com
10.0.x.x      loki-prod.renew.com
10.0.x.x      tempo-prod.renew.com
10.0.x.x      prometheus-prod.renew.com
10.0.x.x      alertmanager-prod.renew.com   # Prometheus alerting 推送 / Loki ruler 推送 :9093
10.0.x.x      k3s-prod.renew.com            # edge-nginx 转发目标 :8083

# ============ ④ 环境级直连服务 ============
# 规范：{service}-{env}.renew.com → 直连数据端口 (写入 hosts.lan)
#       {service}-{env}-ui.renew.com → Web UI (不写 hosts.lan，泛解析→代理)
# env = dev|sit|fat|uat|prod
# Dev 环境（示例，5 环境各写一套）
192.168.x.x   mysql-dev.renew.com         # Pod 直连 :3306
192.168.x.x   redis-dev.renew.com         # Pod 直连 :6379
192.168.x.x   mongodb-dev.renew.com       # Pod 直连 :27017
192.168.x.x   rabbitmq-dev.renew.com      # Pod 直连 :5672 (AMQP)
192.168.x.x   consul-dev.renew.com        # Pod 直连 :8500 (API)
# Web UI 域名不写 hosts.lan（泛解析 → infra-nginx）：
# consul-dev-ui.renew.com, rabbitmq-dev-ui.renew.com 等
# SIT / FAT / UAT 同理: mysql-sit, redis-fat, consul-uat ...

# 生产环境（物理隔离，独立 IP 段）
10.0.x.x      mysql-prod.renew.com
10.0.x.x      redis-prod.renew.com
# ... 其他同理
```

### DNS 解析链路

```
K3s Pod 查询 mysql-dev.renew.com
    │
    ▼
K3s CoreDNS（匹配 .renew.com）
    │
    ▼
转发到 dnsmasq (:53)
    │
    ▼
hosts.lan 精确匹配 → 返回 Dev MySQL IP
```

### 流量入口分离架构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          双入口 + 多环境路由                                 │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │  公网流量 (DMZ 入口 - 物理隔离双节点)                                  │ │
│  │                                                                       │ │
│  │  用户 → 公网 DNS → edge-nginx (nonprod) :443                         │ │
│  │     (解析至非生产独立公网IP)                                          │ │
│  │         ├─ *.dev/sit/fat/uat.web.renew.com → K3s Traefik:8083        │ │
│  │         └─ *.dev/sit/fat/uat.api.renew.com → K3s Traefik:8083        │ │
│  │                    (后端: k3s-nonprod.renew.com:8083)                  │ │
│  │                                                                       │ │
│  │  用户 → 公网 DNS → edge-nginx (prod) :443                            │ │
│  │     (解析至生产专属公网IP)                                            │ │
│  │         ├─ *.prod.web.renew.com → K3s Traefik:8083                   │ │
│  │         └─ *.prod.api.renew.com → K3s Traefik:8083                   │ │
│  │                    (后端: k3s-prod.renew.com:8083)                     │ │
│  │                                                                       │ │
│  │  访问控制: 公开 / IP 白名单                                            │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │  内网流量 (infra-nginx 入口)                                           │ │
│  │                                                                       │ │
│  │  开发者 → dnsmasq 泛解析 → infra-nginx :80                                    │ │
│  │           ├─ {service}.renew.com → 全局服务 (如 gitlab/nexus/harbor)          │ │
│  │           ├─ {service}-nonprod-ui.renew.com → 域级共用 UI (如 grafana-nonprod-ui) │ │
│  │           ├─ {service}-{env}-ui.renew.com → 环境级 UI (如 consul-dev-ui)      │ │
│  │           ├─ *.{env}.web.renew.com → 非生产 K3s Ingress                       │ │
│  │           └─ *.{env}.api.renew.com → 非生产 K3s Ingress                       │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │  TCP 透传 (infra-nginx stream 块)                                     │ │
│  │                                                                       │ │
│  │  :2222 → GitLab SSH                                                   │ │
│  │  :8082 → Nexus Docker Registry                                        │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 流量链路详情与环境对比

#### 1. 测试环境流量路径

**公网流量路径**：

```text
  公网用户
      │
      ▼
  公网 DNS 解析 *.fat.web.renew.com
      │
      ▼
  edge-nginx (nonprod) :443 — DMZ 公网入口
      │
      │  后端配置：k3s-nonprod.renew.com:8083
      │  （这个域名由公网 DNS 或内网 DNS 解析）
      │
      ▼
  K3s 集群节点 IP
      │
      ▼
  K3s Traefik Ingress :8083 — K3s 内部网关
      │
      ▼
  Pod (业务微服务)
```

**内网流量路径**：

```text
内网开发者
      │
      ▼
  内网 DNS (dnsmasq) 解析 *.fat.web.renew.com
      │
      ▼
  infra-nginx :80 — 内网入口
      │
      │  后端配置：k3s-nonprod.renew.com:8083
      │
      ▼
  K3s Traefik Ingress :8083
      │
      ▼
  Pod
```

#### 2. 生产环境流量路径

**公网流量路径**：

```text
  公网用户
      │
      ▼
  公网 DNS 解析 *.prod.web.renew.com
      │
      ▼
  edge-nginx (prod) :443 — DMZ 公网入口
      │
      │  后端配置：k3s-prod.renew.com:8083
      │  （由生产网段 DNS 或公网 DNS 解析）
      │
      ▼
  生产 K3s 集群节点 IP
      │
      ▼
  K3s Traefik Ingress :8083 — K3s 内部网关
      │
      ▼
  Pod (生产微服务)
```

#### 3. 生产与测试网关对比总结

| 项目 | 测试环境 | 生产环境 |
|------|---------|----------|
| **edge-nginx 实例** | tech-edge-nginx-nonprod | tech-edge-nginx-prod |
| **处理域名** | `*.dev/sit/fat/uat.web/api` | `*.prod.web/api` |
| **K3s 后端** | k3s-nonprod.renew.com:8083（非生产 K3s） | k3s-prod.renew.com:8083（生产 K3s） |
| **DNS 解析** | 公网 DNS 或内网 DNS | 公网 DNS 或生产网段 DNS |
| **SSL 证书** | 测试证书 | 生产证书 |
| **部署阶段** | 阶段三（可选） | 阶段五（必须） |

> **访问控制**：edge-nginx 非生产/生产两实例均支持公开访问或 IP 白名单配置，按域名级别精确控制。

---

## 第四部分：安全加固基线

### 全局安全原则

| **原则** | **措施** |
|----------|---------|
| 网络隔离 | 生产环境与非生产环境网络物理隔离，无任何互通路径 |
| 最小权限 | 所有 Exporter 使用专用监控用户，仅授予只读权限 |
| 密码管理 | 按 `{服务缩写}{角色}_{16位随机}` 规则生成，记录在 `env/{service}.md` |
| 配置安全 | `.env` 文件不提交 Git，包含敏感信息的模板使用 `${VAR}` 占位符 |
| 入口安全 | 公网入口仅 edge-nginx，必须配置 HTTPS (TLS 1.2+)，启用限流 |

### 组件级安全配置

| **组件** | **安全要点** |
|----------|-------------|
| dnsmasq | Web UI (5380) 仅调试用，生产关闭或限 IP；53 端口防火墙仅允许局域网 |
| Redis | ACL 规则文件禁用 `CONFIG`、`DEBUG`、`FLUSHALL` 等危险命令 |
| MySQL | Exporter 专用用户仅 PROCESS + REPLICATION CLIENT + SELECT |
| MongoDB | 启用 `security.authorization`，Exporter 用户仅 clusterMonitor + read |
| Consul | 生产环境开启 ACL (`CONSUL_ACL_ENABLE=true`) |
| RabbitMQ | 默认 guest 账户已禁用，必须配置自定义管理员 |
| Apollo | 生产环境开启 Portal 访问认证，限制配置变更权限 |
| Loki | 生产环境启用 `auth_enabled: true` 配置多租户认证 |
| Grafana | 修改默认 admin 密码，生产建议 LDAP/OAuth 认证 |
| Prometheus | 默认无认证，建议通过 Nginx 反代加 basic auth |
| infra-nginx | 生产环境限制来源 IP（仅内网/VPN） |
| edge-nginx | 配置 HTTPS + 限流 + 安全头 + IP 白名单；nonprod/prod 双实例各自独立证书 |

---

## 第五部分：严格部署与投产顺序

按照组件的底层依赖关系（网络 → 存储 → 资产 → 中间件 → 配置中心 → 计算底座 → 网关），严格遵循 **"先全局后局部，先测试后生产"** 的安全原则。

### 部署阶段总览

```
阶段一: 全局基建与资产核心 (内网全局区)
    │
    ▼
阶段二: 配置中心全量初始化 (Dev/SIT/FAT/UAT Apollo 一次到位，仅 Prod 留到阶段四)
    │
    ▼
阶段三: 非生产环境建设 (中间件 + 计算底座 + CI/CD)
    │   ├─ 各环境独立中间件 (MySQL/Redis/MongoDB/RabbitMQ/Consul，K3s 外部部署)
    │   ├─ 非生产 K3s 集群 (仅运行业务微服务)
    │   ├─ 非生产 LGT 观测栈 (K3s 外部部署)
    │   └─ 非生产 CI/CD (GitLab Runner)
    │
    ▼
阶段四: 生产防线建设 (Prod Zone，物理孤岛)
    │
    ▼
阶段五: 外网大门开启 (DMZ 放行 — 生产 edge-nginx)
    │
    ▼
    ✅ 全线贯通，正式对外服务
```

---

### 阶段一：全局基建与资产核心 (内网全局区)

> **目标**：建立企业内网的基础网络、研发资产管理平台。此阶段完成后，开发团队即可进行代码编写和本地开发。

#### 1.1 内部网络路由初始化

| **序号** | **部署内容** | **Skill** | **前置依赖** | **核心动作** |
|---------|-------------|-----------|-------------|-------------|
| 1-1 | 部署 DNS 服务 | `setup-dns` | Docker 环境 | 建立内网统一域名解析，配置 `*.renew.com` 泛解析，规划好全部 hosts.lan 域名映射（包括后续所有服务的域名） |
| 1-2 | 部署内网反代入口 | `setup-infra-nginx` | 1-1 (DNS) | 部署内网统一流量总闸，**部署前预配置好所有反代规则和 IP 域名映射**（见下方预配置清单），包括尚未部署的服务（GitLab/Nexus/Harbor/Grafana/Apollo 等），后续服务部署到位后即自动生效 |

> **infra-nginx 预配置原则**：infra-nginx 在部署时就将**所有已知服务**的反代规则一次性配置完毕。Nginx 后端 upstream 不可达时仅返回 502，不影响自身运行。服务部署到位后域名即自动可用。

**infra-nginx 预配置规范**（部署前按规则一次性配置）：

| **类型** | **域名规范** | **示例** | **说明** |
|---------|------------|---------|------|
| HTTP 反代 — 全局唯一 | `{service}.renew.com` | `gitlab.renew.com` → GitLab 后端 | 仅一套的服务：GitLab、Nexus、Harbor、DNS Web UI |
| HTTP 反代 — 域级共用 UI | `{service}-nonprod-ui.renew.com` / `{service}-prod-ui.renew.com` | `grafana-nonprod-ui.renew.com` → 非生产 Grafana | 非生产/生产各一套的 UI：Grafana、Prometheus UI、Alertmanager（注意 -ui 后缀） |
| HTTP 反代 — 非生产域独有 | `{service}.renew.com` | `apollo.renew.com` → Apollo Portal | 仅非生产域一套：Apollo Portal |
| HTTP 反代 — 环境级 Web UI | `{service}-{env}-ui.renew.com` | `consul-dev-ui.renew.com` → Dev Consul UI | 每环境独立的中间件管理 UI：Consul UI、RabbitMQ UI 等（-ui 后缀区别于直连域名） |
| HTTP 反代 — Apollo Config | `apollo-config-{env}.renew.com` | `apollo-config-fat.renew.com` → FAT Config | 各环境 Apollo Config Service |
| HTTP 反代 — 业务应用 | `*.{env}.web.renew.com` / `*.{env}.api.renew.com` | `*.fat.web.renew.com` → K3s Traefik | 业务流量转发到 K3s Ingress |
| TCP 透传 | 按端口转发 | `:2222` → GitLab SSH，`:8082` → Nexus Docker | TCP 流量直接透传 |

> **说明**：
>
> - 具体的后端端口由各 `setup-*` Skill 自行定义，此处仅规范域名命名规则和反代类型
> - **-ui 后缀普遍适用**（环境级 ④ 和域级共用 ②）：`consul-dev-ui.renew.com`（代理）vs `consul-dev.renew.com`（hosts.lan 直连）；`grafana-nonprod-ui.renew.com`（代理）无对应直连域名
> - 直连域名（otel/loki/tempo/prometheus 数据端口、环境级中间件）写入 hosts.lan；Web UI 域名由泛解析自动落入 infra-nginx

**验证检查点**：

- [ ] 所有服务器 `nslookup *.renew.com` 解析正常
- [ ] `curl http://gitlab.renew.com` 返回 502（GitLab 未部署时属正常，验证 nginx 反代已配置）

#### 1.2 研发资产仓库建设

| **序号** | **部署内容** | **Skill** | **前置依赖** | **核心动作** |
|---------|-------------|-----------|-------------|-------------|
| 1-3 | 部署代码仓库 | `setup-gitlab` | 1-1 (DNS) | 拉起 GitLab，初始化组织架构和项目分组，激活企业版许可证 |
| 1-4 | 部署依赖包私服 | `setup-nexus` | 1-1 (DNS) | 拉起 Nexus，配置 Maven/NPM 代理缓存，添加阿里云等国内镜像源 |
| 1-5 | 部署镜像仓库 | `setup-harbor` | 1-1 (DNS) | 拉起 Harbor，为后续 K3s 拉取业务镜像做准备 |

> **并行说明**：1-3、1-4、1-5 无互相依赖，可**全部并行部署**。
>
> **无需再更新 infra-nginx**：由于 1-2 已预配置好所有反代规则，服务部署到位后域名即自动可用，无需额外操作。

**验证检查点**：

- [ ] `http://gitlab.renew.com` 可登录（infra-nginx 反代自动生效）
- [ ] `http://nexus.renew.com` Maven 代理可用
- [ ] `http://harbor.renew.com` 镜像仓库可访问
- [ ] Docker 配置 `insecure-registries: ["harbor.renew.com"]`

---

### 阶段二：配置中心全量初始化 (非生产 Apollo 一次到位)

> **目标**：一次性搭建完整的非生产配置管理平台。部署完成后，即可登录 Portal 查看和管理 Dev/SIT/FAT/UAT 四个环境的配置。**仅 Prod 生产环境在阶段四单独搭建**。
>
> **合并部署策略**：Apollo 专用 MySQL、Portal、四环境 Config/Admin 由 `setup-apollo --env nonprod` 一个命令一次性拉起，不拆分为"MySQL 先部署、应用后部署"两步，降低依赖协调和时序风险。

| **序号** | **部署内容** | **Skill / 操作** | **前置依赖** | **核心动作** |
|---------|-------------|-----------------|-------------|-------------|
| 2-1 | 一次到位部署非生产 Apollo 全套（MySQL + Portal + 4 环境 Config/Admin） | `setup-apollo --env nonprod` | 1-1 (DNS) | 通过一个 Docker Compose 编排一次性拉起 **10 个容器**：<br>① Apollo 专用 MySQL（初始化 5 个 Schema：`ApolloPortalDB`、`ApolloConfigDB_dev/sit/fat/uat`）<br>② Apollo Portal (:8070)<br>③ Dev/SIT/FAT/UAT Config (:8601-8604)<br>④ Dev/SIT/FAT/UAT Admin (:8611-8614)<br>Portal 中自动配置各环境 Meta Server 地址，使四个环境即刻可用 |

**Apollo 非生产部署详情**：

| **环境** | **Config Service** | **Admin Service** | **数据库 Schema** | **Meta Server 地址** |
|---------|-------------------|-------------------|-------------------|---------------------|
| DEV | `:8601` | `:8611` | `ApolloConfigDB_dev` | `http://apollo-config-dev:8080` |
| SIT | `:8602` | `:8612` | `ApolloConfigDB_sit` | `http://apollo-config-sit:8080` |
| FAT | `:8603` | `:8613` | `ApolloConfigDB_fat` | `http://apollo-config-fat:8080` |
| UAT | `:8604` | `:8614` | `ApolloConfigDB_uat` | `http://apollo-config-uat:8080` |
| Portal | `:8070` | — | `ApolloPortalDB` | — |

> **说明**：`apollo.portal.envs = dev,sit,fat,uat,pro`，其中 PRO 环境此时配置为空占位，在阶段四生产搭建时才接入真实的生产 Config Service。

**验证检查点**：

- [ ] Apollo 专用 MySQL 可连接，5 个数据库（1 Portal + 4 Config）全部已创建
- [ ] `http://apollo.renew.com` Portal 可登录（默认 apollo/admin）
- [ ] Portal 环境列表显示 DEV/SIT/FAT/UAT 四个环境状态均为 **可用**
- [ ] PRO 环境状态为不可用（正常，等阶段四接入）
- [ ] `curl http://apollo-config-dev.renew.com/health` 返回正常
- [ ] `curl http://apollo-config-sit.renew.com/health` 返回正常
- [ ] `curl http://apollo-config-fat.renew.com/health` 返回正常
- [ ] `curl http://apollo-config-uat.renew.com/health` 返回正常

---

### 阶段三：非生产环境建设 (中间件 + 计算底座 + CI/CD)

> **目标**：搭建供研发和测试团队使用的内部环境，并打通自动化部署流水线。
>
> **关键说明**：
>
> - 所有中间件（MySQL/Redis/MongoDB/RabbitMQ/Consul）均在 K3s **外部**以独立 Docker Compose 部署，与 K3s 无关
> - K3s 仅作为纯粹的业务应用运行底座，只负责微服务代码的编排和调度
> - Apollo Config/Admin Service 已在阶段二一次性部署完毕，本阶段无需处理

#### 3.1 Dev 环境中间件部署 (基准环境)

> 所有中间件部署在 K3s 外部的独立物理机/虚拟机上，通过 DNS 域名供 K3s 内的业务 Pod 直连。

| **序号** | **部署内容** | **Skill** | **部署方式** | **前置依赖** | **核心动作** |
|---------|-------------|-----------|-------------|-------------|-------------|
| 3-1 | 部署 Dev 业务 MySQL | `setup-mysql` | K3s 外部独立 Docker Compose | 1-1 (DNS) | 独立物理机/虚拟机部署，域名: `mysql-dev.renew.com` |
| 3-2 | 部署 Dev Redis | `setup-redis` | K3s 外部独立 Docker Compose | 1-1 (DNS) | 独立部署，域名: `redis-dev.renew.com` |
| 3-3 | 部署 Dev MongoDB | `setup-mongodb` | K3s 外部独立 Docker Compose | 1-1 (DNS) | 独立部署，域名: `mongodb-dev.renew.com` |
| 3-4 | 部署 Dev RabbitMQ | `setup-rabbitmq` | K3s 外部独立 Docker Compose | 1-1 (DNS) | 独立部署，域名: `rabbitmq-dev.renew.com` |
| 3-5 | 部署 Dev Consul | `setup-consul` | K3s 外部独立 Docker Compose | 1-1 (DNS) | 独立部署，域名: `consul-dev.renew.com` |

> **并行说明**：3-1 ~ 3-5 无互相依赖，可**全部并行部署**。

**验证检查点**：

- [ ] Dev MySQL 可连接: `mysql -h mysql-dev.renew.com -P 3306`
- [ ] Dev Redis 可连接: `redis-cli -h redis-dev.renew.com ping`
- [ ] Dev MongoDB 可连接: `mongosh mongodb-dev.renew.com:27017`
- [ ] Dev RabbitMQ 管理 UI 可访问: `rabbitmq-dev.renew.com:15672`
- [ ] Dev Consul UI 可访问: `consul-dev.renew.com:8500`

#### 3.2 横向扩展测试环境中间件 (SIT/FAT/UAT)

**复制 Dev 模式**，为 SIT、FAT、UAT 各部署一套**完全独立的**中间件（均在 K3s 外部独立部署）：

| **操作** | **SIT** | **FAT** | **UAT** |
|---------|---------|---------|---------|
| MySQL (独立 Docker Compose) | `mysql-sit.renew.com` | `mysql-fat.renew.com` | `mysql-uat.renew.com` |
| Redis (独立 Docker Compose) | `redis-sit.renew.com` | `redis-fat.renew.com` | `redis-uat.renew.com` |
| MongoDB (独立 Docker Compose) | `mongodb-sit.renew.com` | `mongodb-fat.renew.com` | `mongodb-uat.renew.com` |
| RabbitMQ (独立 Docker Compose) | `rabbitmq-sit.renew.com` | `rabbitmq-fat.renew.com` | `rabbitmq-uat.renew.com` |
| Consul (独立 Docker Compose) | `consul-sit.renew.com` | `consul-fat.renew.com` | `consul-uat.renew.com` |

> **效率建议**：各环境的中间件部署可并行执行（部署在不同物理机/虚拟机上）。
>
> **Apollo 无需操作**：各环境的 Apollo Config/Admin Service 已在阶段二一次性部署完毕，无需在此阶段重复处理。

#### 3.3 非生产计算底座与观测平台

| **序号** | **部署内容** | **Skill** | **部署方式** | **前置依赖** | **核心动作** |
|---------|-------------|-----------|-------------|-------------|-------------|
| 3-6 | 部署非生产 K3s 集群 | `setup-k3s` | 独立物理机/虚拟机 | 1-1 (DNS) | 建立非生产 K3s 集群（仅运行业务微服务），创建 Namespace: `dev`, `sit`, `fat`, `uat`；配置 CoreDNS 转发 `.renew.com` 到 dnsmasq，使 Pod 可通过 DNS 直连外部中间件 |
| 3-7 | 部署非生产 LGT 栈 | `setup-tempo` + `setup-loki` + `setup-prometheus` + `setup-grafana` + `setup-otel-collector` | K3s **外部**独立服务器 (Docker Compose) | 1-1 (DNS) | 在 K3s 外部独立服务器拉起完整可观测性栈；env 标签由 app.sh 通过 `OTEL_RESOURCE_ATTRIBUTES` 环境变量注入（详见 `observability-env-isolation.md`） |

> **并行说明**：3-6 和 3-7 无直接依赖，可并行部署。但 LGT 栈内部需按依赖顺序：Tempo/Loki → Prometheus → Grafana + OTel Collector。

#### 3.4 非生产 CI/CD 闭环

| **序号** | **部署内容** | **Skill** | **部署方式** | **前置依赖** | **核心动作** |
|---------|-------------|-----------|-------------|-------------|-------------|
| 3-8 | 一站式部署非生产 CI/CD 执行环境 | `setup-gitlab-runner` | K3s **外部**独立节点 (Docker Compose) | 1-3 (GitLab), 1-5 (Harbor), 3-6 (K3s) | 一次性完成：静态工具下载 → app.sh/settings.xml 上传 → kubeconfig 配置 → 基础镜像推送 → Runner 容器启动；注册后打上 `tag: non-prod` |
| 3-9 | 导入 Apollo 配置模板 | `setup-cicd` | — | 2-1 (Apollo) | 将 `apollo-tech-common.properties` 导入 Apollo `tech.common` namespace（首次部署必做） |
| 3-10 | Demo 端到端验证 | `setup-cicd demo` | — | 3-8, 3-9 | 推送 Demo 项目验证完整 Pipeline 链路 |
| 3-11 | 编写 CI/CD Pipeline | `.gitlab-ci.yml` | — | 3-8 | 配置开发分支提交后的自动化流水线：编译 → 打包镜像 → 推至 Harbor → 部署至对应 K3s Namespace |

**Pipeline 验证**：

- [ ] 开发分支提交触发 CI/CD，`non-prod` Runner 接管
- [ ] 镜像成功推送至 Harbor
- [ ] 微服务 Pod 在 `dev` Namespace 正常运行
- [ ] Pod 通过 DNS 直连 K3s 外部的 Dev 环境独立中间件（MySQL/Redis/Consul 等）
- [ ] Pod 通过 `apollo-config-dev.renew.com` 成功拉取 Apollo 配置

#### 3.5 非生产公网入口（可选）

> **目标**：为非生产环境提供公网访问入口，方便外部测试人员访问。

| **序号** | **部署内容** | **Skill** | **部署位置** | **核心动作** |
|---------|-------------|-----------|-------------|-------------|
| 3-12 | 部署非生产边缘网关 | `setup-edge-nginx --env nonprod` | 非生产域 DMZ 节点 (独立公网 IP) | 处理 dev/sit/fat/uat 公网流量，配置 IP 白名单访问控制 |

---

### 阶段四：生产防线建设 (Prod Zone)

> **目标**：打造与测试环境完全物理隔离的"生产孤岛"，应对金融级安全合规审查。

#### 4.1 生产独立中间件建设

> 初期与测试环境保持一致，采用单实例 Docker Compose 部署。后续可按需升级为高可用架构（见第一部分 4.2 备注）。

| **序号** | **部署内容** | **Skill** | **部署方式** | **核心动作** |
|---------|-------------|-----------|-------------|-------------|
| 4-1 | 部署生产 MySQL | `setup-mysql` | K3s 外部独立 Docker Compose | 生产专属独立实例，域名: `mysql-prod.renew.com` |
| 4-2 | 部署生产 Redis | `setup-redis` | K3s 外部独立 Docker Compose | 生产专属独立实例，域名: `redis-prod.renew.com` |
| 4-3 | 部署生产 MongoDB | `setup-mongodb` | K3s 外部独立 Docker Compose | 生产专属独立实例，域名: `mongodb-prod.renew.com` |
| 4-4 | 部署生产 RabbitMQ | `setup-rabbitmq` | K3s 外部独立 Docker Compose | 生产专属独立实例，域名: `rabbitmq-prod.renew.com` |
| 4-5 | 部署生产 Consul | `setup-consul` | K3s 外部独立 Docker Compose | 生产专属独立实例，域名: `consul-prod.renew.com` |

> **并行说明**：4-1 ~ 4-5 无互相依赖，可全部并行部署。

**验证检查点**：

- [ ] 生产中间件全部独立运行，域名解析正确

#### 4.2 生产配置中心接入

> **合并部署策略**：生产 Apollo 专用 MySQL + Config + Admin 由 `setup-apollo --env prod` 一个命令一次性拉起，与非生产阶段二合并部署策略一致。

| **序号** | **部署内容** | **Skill / 操作** | **核心动作** |
|---------|-------------|-----------------|-------------|
| 4-6 | 一次到位部署生产 Apollo 全套（MySQL + Config + Admin） | `setup-apollo --env prod` | 通过一个 Docker Compose 编排在生产网段一次性拉起 **3 个容器**：<br>① 生产 Apollo 专用 MySQL（初始化 `ApolloConfigDB_prod`）<br>② 生产 Config Service (:8605)<br>③ 生产 Admin Service (:8615)<br>与非生产 Apollo MySQL 完全物理隔离 |
| 4-7 | Portal 跨网段挂载 | Portal 配置 | 在全局 Apollo Portal 中配置 `PRO` 环境的 Meta Server 路由，指向生产 Config Service 地址。Portal 可在内网统一管理生产配置，但**后端数据完全独立** |

**验证检查点**：

- [ ] Apollo Portal 中 PRO 环境状态变为可用
- [ ] 生产 Config Service 健康检查通过

#### 4.3 生产独立底座建设

| **序号** | **部署内容** | **Skill** | **核心动作** |
|---------|-------------|-----------|-------------|
| 4-8 | 部署生产 K3s 集群 | `setup-k3s` | 在全新物理机或隔离 VPC 内拉起生产 K3s 集群，配置 CoreDNS 转发 `.renew.com` 到 dnsmasq，使生产 Pod 可通过 DNS 直连生产中间件 |
| 4-9 | 部署生产 LGT 栈 | `setup-tempo --env prod` + `setup-loki --env prod` + `setup-prometheus --env prod` + `setup-grafana --env prod` + `setup-otel-collector --env prod` | 在完全独立的服务器上拉起生产专用监控系统 |

> **并行说明**：4-8 和 4-9 无直接依赖，可并行部署。

#### 4.4 生产构建节点部署

| **序号** | **部署内容** | **Skill** | **前置依赖** | **核心动作** |
|---------|-------------|-----------|-------------|-------------|
| 4-10 | 一站式部署生产 CI/CD 执行环境 | `setup-gitlab-runner` | 1-3 (GitLab), 1-5 (Harbor), 4-8 (生产 K3s) | 在生产网段内拉起专属 Runner + 执行环境，打上 `tag: prod`，确保生产编译和发布仅在安全网络域内执行 |

---

### 阶段五：外网大门开启 (DMZ 放行)

> **目标**：将网络入口打通，迎接真实用户流量。这是整个部署的**最后一步**。

#### 5.1 网关路由配置

| **序号** | **部署内容** | **Skill** | **核心动作** |
|---------|-------------|-----------|-------------|
| 5-1 | 部署生产边缘网关 | `setup-edge-nginx --env prod` | 在生产专属的公网 DMZ 服务器（独立公网 IP、独立机房）上拉起生产 edge-nginx，配置 SSL 证书和路由规则 |
| 5-2 | 配置公网 DNS 解析 | 公网 DNS 服务商 | 将生产域名（如 `*.prod.web/api.renew.com`）解析到生产专属的 edge-nginx 公网 IP |
| 5-3 | 添加白名单路由（可选） | `setup-edge-nginx add-route` | 为管理后台等受限域名配置 IP 白名单 |

#### 5.2 生产自动化发版流程启动

```
开发侧触发 master 分支合并或打上 Release Tag (如 v1.0.0)
    │
    ▼
GitLab CI/CD 触发 Pipeline
    │
    ▼
tag: prod 的 Runner 接管
    │
    ├─ 编译构建 (Maven/Gradle)
    ├─ 打包镜像 → 推送 Harbor
    ├─ 拉取生产 Apollo 配置
    └─ kubectl apply → 生产 K3s 集群
    │
    ▼
业务 Pod 滚动更新
    │
    ▼
K3s Traefik Ingress 路由生效 → edge-nginx 透传 → 用户可访问
    │
    ▼
✅ 生产环境全线贯通，正式对外服务
```

**上线验证清单**：

- [ ] edge-nginx HTTPS 证书有效，域名解析正确
- [ ] 生产 K3s Pod 全部 Running，健康检查通过
- [ ] 业务 API 端到端测试通过
- [ ] 生产 Grafana 监控看板数据正常
- [ ] 告警规则已配置并生效（Alertmanager → 钉钉/邮件）

---

## 附录 A：技术栈版本清单

| **分层** | **服务** | **版本** | **端口** | **用途** |
|---------|---------|---------|---------|---------|
| DNS | dnsmasq | latest | 53 / 5380 | 局域网域名解析 |
| 内部入口 | infra-nginx | 1.27 | 80 / 2222 / 8082 | 内部 Web UI 统一入口 |
| 接入层 | edge-nginx | 1.27 | 80 / 443 | 公网边缘网关（DMZ） |
| 数据存储 | MySQL | 8.4 LTS | 3306 | 业务主数据库 |
| 数据存储 | Redis | 8.0 | 6379 | 缓存 / 分布式锁 / 会话 |
| 数据存储 | MongoDB | 8.0 | 27017 | 文档数据库 |
| 消息中间件 | RabbitMQ | 4.0 | 5672 / 15672 / 15692 | 异步消息 / Quorum Queue |
| 服务治理 | Consul | 1.20 | 8500 / 8600 | 服务注册与发现 |
| 服务治理 | Apollo | 2.5.0 | 8070 / 8601-8605 / 8611-8615 | 分布式配置中心 |
| 可观测性 | OTel Collector | 0.120.0 | 4317 / 4318 / 8888 | 统一遥测数据网关 |
| 可观测性 | Tempo | 2.7.0 | 3200 | 分布式链路追踪 |
| 可观测性 | Loki | 3.5.0 | 3100 | 日志聚合 |
| 可观测性 | Prometheus + Alertmanager | v3.2 / v0.28 | 9090 / 9093 | 指标采集 + 告警 |
| 可观测性 | Grafana | 11.4 | 3000 | 统一可视化看板 |
| 研发支撑 | GitLab EE | 17.8 | 8929 / 8443 / 2222 | 代码托管 + CI/CD |
| 研发支撑 | GitLab Runner | 17.8 | — | CI/CD 执行器 |
| 研发支撑 | Nexus OSS | 3.87 | 8081 / 8082 | Maven/NPM 私服 |
| 研发支撑 | Harbor | 2.12 | 8880 | Docker 镜像仓库 |
| 业务应用 | K3s (含内置 Traefik Ingress) | v1.32 | 6443 / 8083 | 业务应用编排平台，8083 为 K3s 内置 Traefik Ingress 端口 |

### 业务框架版本对应

| **业务框架** | **版本** | **对应基础设施** |
|-------------|---------|----------------|
| JDK | 21（主力）/ 11（兜底） | JDK 21 用于 Spring Boot 3.x 方案 A；JDK 11 用于 Spring Boot 2.x 方案 B |
| Spring Boot | 3.5.x（主力）/ 2.7.x（兜底） | 3.x 采用 Micrometer + Bridge；2.x 采用 Java Agent |
| Spring Cloud | 2025.0.0 (Northfields) | Consul 1.20 |
| Apollo Client | 2.4.0 | Apollo 2.5.0 |
| Redisson | 4.3.0 | Redis 8.0 |
| Spring AMQP | 4.x | RabbitMQ 4.0 |
| **Micrometer Tracing** | 1.4.x | 方案 A 链路桥接，Spring Boot 3.x 内置 |
| **Micrometer Prometheus** | — | 方案 A/B 共用，产出 `/actuator/prometheus` 端点 |
| **OTel SDK (Bridge)** | 1.45+ | 方案 A 使用，配合 Micrometer Tracing 导出 OTLP |
| **OTel Java Agent** | 2.11.x | 方案 B 使用，JDK 8+ 兼容，SB 2.x 兜底 |
| OTel Collector | 0.120.0 | 统一 OTLP 接收网关 |
| Tempo | 2.7.0 | 链路后端 |
| Loki | 3.5.0 | 日志后端 |
| Prometheus | 3.2 | 指标拉取 + 告警 |
| Grafana | 11.4 | 统一看板 |

---

## 附录 B：setup-* Skill 与组件映射表

### B.1 部署次数与 `--env` 参数约定

| **Skill** | **服务** | **全局区** | **非生产×4** | **生产** | **部署次数** | **`--env` 取值** |
|-----------|---------|-----------|------------|---------|------------|----------------|
| `setup-dns` | dnsmasq | ✅ (1套) | — | — | 1 | 不接受 |
| `setup-infra-nginx` | infra-nginx | ✅ (1套) | — | — | 1 | 不接受 |
| `setup-gitlab` | GitLab EE | ✅ (1套) | — | — | 1 | 不接受 |
| `setup-nexus` | Nexus | ✅ (1套) | — | — | 1 | 不接受 |
| `setup-harbor` | Harbor | ✅ (1套) | — | — | 1 | 不接受 |
| `setup-apollo` | Apollo 全套（MySQL+Portal+Config+Admin） | — | ✅ (nonprod ×1 含 10 容器) | ✅ (prod ×1 含 3 容器) | 2 | `nonprod\|prod` |
| `setup-mysql` | 业务 MySQL | — | ✅ (4套) | ✅ (1套) | 5 | `dev\|sit\|fat\|uat\|prod` |
| `setup-redis` | Redis | — | ✅ (4套) | ✅ (1套) | 5 | `dev\|sit\|fat\|uat\|prod` |
| `setup-mongodb` | MongoDB | — | ✅ (4套) | ✅ (1套) | 5 | `dev\|sit\|fat\|uat\|prod` |
| `setup-rabbitmq` | RabbitMQ | — | ✅ (4套) | ✅ (1套) | 5 | `dev\|sit\|fat\|uat\|prod` |
| `setup-consul` | Consul | — | ✅ (4套) | ✅ (1套) | 5 | `dev\|sit\|fat\|uat\|prod` |
| `setup-k3s` | K3s | — | ✅ (1套共用) | ✅ (1套) | 2 | `nonprod\|prod` |
| `setup-loki` | Loki | — | ✅ (1套共用) | ✅ (1套) | 2 | `nonprod\|prod` |
| `setup-prometheus` | Prometheus | — | ✅ (1套共用) | ✅ (1套) | 2 | `nonprod\|prod` |
| `setup-tempo` | Tempo | — | ✅ (1套共用) | ✅ (1套) | 2 | `nonprod\|prod` |
| `setup-otel-collector` | OTel Collector | — | ✅ (1套共用) | ✅ (1套) | 2 | `nonprod\|prod` |
| `setup-grafana` | Grafana | — | ✅ (1套共用) | ✅ (1套) | 2 | `nonprod\|prod` |
| `setup-gitlab-runner` | Runner + CI Job 执行环境 | — | ✅ (non-prod ×1) | ✅ (prod ×1) | 2 | `nonprod\|prod` |
| `setup-edge-nginx` | edge-nginx | — | ✅ (非生产公网 ×1) | ✅ (生产公网 ×1) | 2 | `nonprod\|prod` |
| `setup-cicd` | 业务接入指导（demo/integrate） | — | — | — | 0（仅引用） | 不接受（demo/integrate） |

> **总计**：整套完整部署涉及约 **42 次** `setup-*` Skill 调用（Apollo 合并后从 48 次减少）。

### B.2 `--env` 参数标准契约

| **类型** | **适用 Skill** | **取值** | **默认值** | **传错处理** |
|---------|---------------|---------|-----------|-------------|
| A. 环境级完全独立 | `setup-mysql` / `setup-redis` / `setup-mongodb` / `setup-rabbitmq` / `setup-consul` | `dev\|sit\|fat\|uat\|prod` | `dev` | 报错退出 |
| B. 域级共用+生产独立 | `setup-k3s` / `setup-loki` / `setup-prometheus` / `setup-tempo` / `setup-otel-collector` / `setup-grafana` / `setup-gitlab-runner` / `setup-edge-nginx` | `nonprod\|prod` | `nonprod` | 报错退出 |
| C. 全局唯一 | `setup-dns` / `setup-infra-nginx` / `setup-gitlab` / `setup-nexus` / `setup-harbor` | 不接受 | — | 传入即报错 |
| D. Apollo 特殊合并 | `setup-apollo` | `nonprod\|prod`（nonprod 内含 4 子环境） | `nonprod` | 报错退出 |
| E. 业务接入指导 | `setup-cicd` | 不接受（action 为 `demo\|integrate`，非 `--env` 参数） | — | — |

---

## 版本历史

| **版本** | **日期** | **变更** |
|---------|---------|---------|
| 1.9.0 | 2026-04-27 | ② 域级直连数据端口扩展 alertmanager：将 `alertmanager-{nonprod\|prod}.renew.com:9093` 纳入 hosts.lan 必备清单（5 服务 × 2 域 = 10 条 → 6 服务 × 2 域 = 12 条；hosts.lan 总条数 35 → 37）。原因：Prometheus alerting 与 Loki ruler 需通过域名跨节点推送告警到 Alertmanager，原 ② 域级直连仅含 otel/loki/tempo/prometheus/k3s 时该域名无解析路径 |
| 1.8.0 | 2026-04-23 | 拆分第二部分 LGT 栈 env 标签隔离方案为独立文档 `observability-env-isolation.md`，蓝图章节重新编号（第二~六部分 → 第二~五部分） |
| 1.7.0 | 2026-04-21 | 优化 OTel Agent 部署方式（6.3.1 节）：(1) Agent 由 `setup-gitlab-runner` 统一管理，存放在宿主机 `/opt/tech-stack/cicd/` 并通过 volumes 挂载到容器；(2) 不再要求基础镜像预置 Agent；(3) 优势：跨 JDK 8~21 版本通用、更新只需替换文件、无需维护多个基础镜像 |
| 1.6.0 | 2026-04-21 | 第二部分重构为双方案并存结构：(1) 新增方案 A「Micrometer Observation + OTel Bridge」作为 Spring Boot 3.x 主力方案；(2) 原 Java Agent 降级为方案 B，仅用于 Spring Boot 2.x 兜底；(3) 明确 Metrics 走 Prometheus 拉取、Traces/Logs 走 OTLP 推送的通路解耦设计；(4) 补充 Micrometer Tracing / OTel Agent 版本到附录 A；(5) 新增 `ops.otelMode` 配置项；(6) 补充 Prometheus consul_sd 的 `metrics` 标签前提条件和基础设施抓取目标清单；(7) 补充方案 A/B 的 application.yml 完整示例（含 Consul 注册配置） |
| 1.5.0 | 2026-04-21 | 重构第二部分 LGT 栈 env 标签隔离方案：(1) 移除 DaemonSet Agent 和 kubernetes_sd_configs；(2) 统一使用 SDK 环境变量注入 `OTEL_RESOURCE_ATTRIBUTES`；(3) 增加 Spring Boot 接入指南和 `ops.supportOtel` 条件启用说明 |
| 1.4.0 | 2026-04-18 | 修正 Apollo nonprod 容器数量（11→10），实际为 MySQL×1 + Portal×1 + Config×4 + Admin×4 = 10 容器 |
| 1.3.1 | 2026-04-17 | 移除 `nginx.renew.com` 域名（infra-nginx 无管理 UI，无需专属域名） |
| 1.3.0 | 2026-04-17 | 职责重组：(1) `setup-gitlab-runner` 吸收 CI Job 执行环境准备（app.sh、kubeconfig、静态工具、基础镜像），一站式部署；(2) `setup-cicd` 职责收缩为业务接入指导（demo/integrate）；(3) 更新阶段三 CI/CD 部署步骤，移除冗余的 Harbor Secret 创建（由 app.sh 自动处理） |
| 1.2.0 | 2026-04-17 | 两项关键优化：(1) Apollo 合并部署 —— Apollo MySQL 由 `setup-apollo` 内置管理，`--env nonprod` 一次拉起 10 容器，`--env prod` 一次拉起 3 容器，setup-mysql 退回仅 5 次业务部署；(2) 附录 B 新增 `--env` 参数标准契约（6 类分类表），明确每个 skill 的多环境部署参数 |
| 1.1.0 | 2026-04-16 | 三项核心优化：(1) infra-nginx 改为部署前预配置全部反代规则；(2) Apollo 阶段二一次性完成四个非生产环境全部初始化；(3) 明确所有中间件在 K3s 外部独立 Docker Compose 部署 |
| 1.0.0 | 2026-04-16 | 初始版本：基于参考文档与正式文档整合优化，输出完整架构蓝图 |
