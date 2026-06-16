# Tech Stack Setup

> **FinTech 级多环境隔离微服务基础设施部署方案** — 基于 Docker Compose + K3s 混合架构，覆盖 Spring Boot 3.5 + Spring Cloud 2025.0 + JDK 21 体系。
>
> 每个服务对应一个 `setup-*` skill，通过 SSH（Python paramiko）远程部署到目标服务器。

---

## 架构总览

```
┌─────────────────────────────────────────────────────────────────────┐
│              全局共享层（Global Internal Zone，1 套）                  │
│  网络基座: setup-dns · setup-infra-nginx                            │
│  研发资产: setup-gitlab · setup-nexus · setup-harbor                │
└─────────────────────────────────────────────────────────────────────┘
                                │
                  ┌─────────────┴─────────────┐
                  ▼                           ▼
       ┌──────────────────┐         ┌──────────────────┐
       │  非生产域 NonProd │         │  生产域 Prod      │
       │                  │         │  （物理孤岛）     │
       │  共用 1 套:       │         │  独立 1 套:       │
       │   K3s + LGT 栈    │         │   K3s + LGT 栈    │
       │   GitLab Runner  │         │   GitLab Runner  │
       │   Apollo (10 容器)│         │   Apollo (3 容器) │
       │                  │         │                  │
       │  环境级独立 4 套: │         │  环境级独立 1 套: │
       │   MySQL × 4      │         │   MySQL × 1      │
       │   Redis × 4      │         │   Redis × 1      │
       │   MongoDB × 4    │         │   MongoDB × 1    │
       │   RabbitMQ × 4   │         │   RabbitMQ × 1   │
       │   Consul × 4     │         │   Consul × 1     │
       │  Dev/SIT/FAT/UAT │         │  Prod            │
       └────────┬─────────┘         └────────┬─────────┘
                ▼                            ▼
     ┌──────────────────────┐   ┌──────────────────────┐
     │ DMZ edge-nginx       │   │ DMZ edge-nginx       │
     │ (nonprod 独立公网 IP) │   │ (prod 独立公网 IP)    │
     └──────────────────────┘   └──────────────────────┘
            │                              │
            ▼                              ▼
     公网用户访问 *.{env}.web/api.renew.com
```

> **三大逻辑域 + 两条 DMZ 安全边界**。详细拓扑见 [架构蓝图](architecture-blueprint.md)。

### 部署五阶段

```
阶段一: 全局基建      DNS → infra-nginx → GitLab/Nexus/Harbor (并行)
   ↓
阶段二: 配置中心      Apollo nonprod (10 容器一次到位)
   ↓
阶段三: 非生产建设    中间件 ×4 环境 → K3s nonprod → LGT nonprod → Runner → CI/CD demo
   ↓
阶段四: 生产防线      中间件 prod → Apollo prod (3 容器) → K3s prod → LGT prod → Runner
   ↓
阶段五: 外网放行      edge-nginx prod (DMZ) → 公网 DNS 解析 → 全线贯通
```

---

## 快速开始

### 前置条件

每台服务器需要：

1. **Docker Engine 24+** 和 Docker Compose Plugin（新机器可用 `curl -fsSL https://get.docker.com | sh` 一键安装）
2. **内核参数**：`net.bridge.bridge-nf-call-iptables=1`、`net.ipv4.ip_forward=1`（详见 [部署原则](references/deployment-principles.md)）
3. **DNS 已配置** — 部署 `setup-dns` 后执行 `/setup-dns configure --dns-server <IP>` 配置每台机器解析

### 安装 Skills

```bash
# 批量安装
for d in setup-*/; do (cd "$d" && bash install.sh); done

# 或单独安装
cd setup-mysql && bash install.sh
```

### 部署命令

```bash
# 全局唯一 Skill（C 类）
/setup-dns start --host <IP> --user root --key ~/.ssh/id_rsa
/setup-infra-nginx start --host <IP> --user root --password <pwd>

# 环境级独立 Skill（A 类，必传 --env）
/setup-mysql start --env dev --host <IP> --user root --key ~/.ssh/id_rsa
/setup-redis start --env fat --host <IP> --user root --password <pwd>

# 域级共用 Skill（B 类）
/setup-k3s start --env nonprod --host <IP> --user root --key ~/.ssh/id_rsa
/setup-grafana start --env prod --host <IP> --user root --password <pwd>

# Apollo 合并部署（D 类）
/setup-apollo start --env nonprod --host <IP> --user root --key ~/.ssh/id_rsa  # 10 容器
/setup-apollo start --env prod    --host <IP> --user root --password <pwd>     # 3 容器
```

> **完整流程**（hosts.lan 规划、跨服务 `.env` 变量、五阶段编排）：见 [部署原则](references/deployment-principles.md) 和 [部署指南模板库](references/deployment-guide/)。
>
> **AI 决策上下文 + 跨服务参数表**：见 [CLAUDE.md](CLAUDE.md)。

---

## 服务概览

> 完整端口 / 域名 / 多环境部署次数详见 [CLAUDE.md 服务注册表](CLAUDE.md#服务注册表)。

| 分层 | 服务 | 用途 |
|------|------|------|
| **全局共享层** |||
| DNS | dnsmasq | 局域网 *.renew.com 域名解析（架构基石，最先部署） |
| 内部入口 | infra-nginx | 内部 Web UI 统一反代 + SSH/Docker stream 透传 + 业务域名内网直达 K3s |
| 研发支撑 | GitLab EE 17.8 | 代码托管 + CI/CD（企业版，含许可证激活） |
| 研发支撑 | Nexus 3.87 OSS | Maven 私有仓库 + Docker Registry |
| 研发支撑 | Harbor 2.12 | Docker 镜像仓库 + Trivy 漏洞扫描 |
| **环境级独立层（每环境独立实例）** |||
| 数据存储 | MySQL 8.4 LTS | 业务主数据库（与 Apollo 专用 MySQL 完全分离） |
| 数据存储 | Redis 8.0 | 缓存 / 分布式锁 / 会话；ACL 三类用户最小权限 |
| 数据存储 | MongoDB 8.0 | 文档数据库；启用 `security.authorization` |
| 消息中间件 | RabbitMQ 4.0 | 异步消息 / Quorum Queue；内置 Prometheus 指标插件 |
| 服务治理 | Consul 1.20 | 服务注册与发现，作为 Prometheus consul_sd 源 |
| **域级共用层（nonprod 4 环境共用 + prod 独立）** |||
| 业务应用 | K3s v1.32 | 业务应用编排平台（前端 / Gateway / 微服务） |
| 可观测性 | OTel Collector 0.120 | Traces/Logs 统一接收网关 |
| 可观测性 | Tempo 2.7 | 分布式链路追踪后端 |
| 可观测性 | Loki 3.5 | 日志聚合后端，OTLP 原生接收 |
| 可观测性 | Prometheus v3.2 + Alertmanager v0.28 | 指标采集 + 告警；nonprod 采集 4 套环境 |
| 可观测性 | Grafana 11.4 | 统一可视化看板（Trace↔Log↔Metrics 三向跳转） |
| 研发支撑 | GitLab Runner 17.8 | CI/CD 执行器 + CI Job 执行环境一站式部署 |
| 接入层 | edge-nginx 1.27 | 公网业务流量入口（DMZ 区），nonprod/prod 双实例物理隔离 |
| **配置中心（D 类合并部署）** |||
| 服务治理 | Apollo 2.5.0 | nonprod 一次拉起 10 容器 + prod 一次拉起 3 容器；内置专用 MySQL |
| **业务接入指导（E 类）** |||
| 研发支撑 | setup-cicd | demo 端到端验证 + integrate.md 业务接入指南（不部署基础设施） |

---

## 安全加固检查清单

> 部署完成后逐项确认。核心原则：所有密码 `CHANGE_ME_*` 占位符必须替换；`.env` 已 `.gitignore` 禁止提交；公网入口仅 edge-nginx 且必须 HTTPS。

### 全局密码与凭据

- [ ] 所有 `CHANGE_ME_*` 密码占位符已按 `{服务缩写}{角色}_{16位随机}` 规则替换并记录在 `env/<service>.md`
- [ ] `.env` 文件未入 git（`.gitignore` 已含 `**/.env`）
- [ ] kubeconfig（`/etc/rancher/k3s/k3s.yaml`）禁止入 git，备份至安全位置

### 各服务安全要点

- [ ] **dnsmasq**：Web UI（:5380）生产环境关闭或限 IP；:53 防火墙仅允许局域网
- [ ] **infra-nginx / edge-nginx**：内部入口限来源 IP（内网/VPN）；外部入口配置 HTTPS（TLS 1.2+）+ HSTS + 限流 + IP 白名单
- [ ] **GitLab**：默认禁用公开注册；首次登录修改 root 密码；许可证 Plan 验证为 `ultimate`；启用 SMTP
- [ ] **Nexus**：首次登录修改 admin 密码（`/nexus-data/admin.password`）；禁用匿名访问
- [ ] **Harbor**：修改 admin 密码；启用 Trivy 漏洞扫描；生产建议启用 HTTPS
- [ ] **MySQL**：root 限 localhost；exporter 仅 `PROCESS+REPLICATION CLIENT+SELECT`；3306 防火墙限应用网段
- [ ] **Redis**：ACL 三类用户（default/app/exporter），app 禁用 flushdb/shutdown 等危险命令；exporter 最小白名单
- [ ] **MongoDB**：启用 `security.authorization`；exporter 仅 `clusterMonitor + read on local`
- [ ] **RabbitMQ**：默认 guest 仅 localhost；自定义管理员；Quorum Queue 业务声明
- [ ] **Consul**：**生产环境必须开启 ACL** + Gossip 加密（`CONSUL_ENCRYPT_KEY`）
- [ ] **Apollo**：首次登录修改 Portal 默认密码（apollo/admin）；生产开启访问认证
- [ ] **Loki**：**生产环境 `LOKI_AUTH_ENABLED=true`** 启用多租户认证
- [ ] **Grafana**：必须修改 `GRAFANA_ADMIN_PASSWORD`；生产建议 LDAP/OAuth
- [ ] **Prometheus / Alertmanager**：默认无认证，生产通过 infra-nginx 反代加 basic auth
- [ ] **Harbor / K3s**：生产建议用 Robot Account（只读）替代 admin 密码，存储在 namespace `harbor-registry` Secret

---

## 文档导航

| 文档 | 适合谁读 |
|------|---------|
| [CLAUDE.md](CLAUDE.md) | AI 决策上下文，含服务注册表、跨服务配置绑定、版本矩阵、四层域名规范 |
| [架构蓝图](architecture-blueprint.md) | 任何架构决策必读全文（最终权威） |
| [references/](references/) | 全套架构设计文档（按主题分类） |
| ↳ [部署原则](references/deployment-principles.md) | Docker / 内核参数 / Exporter 用户 / 密码生成规则 / 版本兼容踩坑 |
| ↳ [网络架构](references/network-architecture.md) | 双入口流量路径、DNS 解析机制、四层域名规范 |
| ↳ [配置参考](references/configuration-reference.md) | 跨节点连接清单、环境变量全表 |
| ↳ [可观测性数据流](references/observability-pipeline.md) | OTel→Tempo/Loki/Prometheus 数据流 + 双方案接入 + env 标签注入 |
| ↳ [请求生命周期](references/request-lifecycle.md) | 端到端案例（含多环境），新人入门 |
| ↳ [资源规划](references/resource-planning.md) | 资源估算、高可用演进、备份策略 |
| ↳ [部署指南模板库](references/deployment-guide/) | 五阶段 21 个 task 模板，按需生成 deployment-plan |
| [Spring Boot 接入](setup-cicd/actions/integrate.md) | 业务接入全套基础设施（双方案 + 关闭 OTel 三套示例） |
| [app.sh 部署规范](setup-gitlab-runner/references/app-sh-spec.md) | K8s 资源结构（Deployment/HPA/PDB/Service/Ingress/PVC） |

---

## Skill 清单

| Skill | 类别 | 用法 |
|-------|------|------|
| `setup-dns` | 网络基座（C 全局唯一） | `/setup-dns start \| stop \| status \| verify \| logs \| configure --dns-server <IP>` |
| `setup-infra-nginx` | 网络基座（C） | `/setup-infra-nginx start \| stop \| status \| verify \| logs` |
| `setup-gitlab` | 研发资产（C） | `/setup-gitlab start \| stop \| status \| verify \| logs \| activate \| create-user` |
| `setup-nexus` | 研发资产（C） | `/setup-nexus start \| stop \| status \| verify \| logs` |
| `setup-harbor` | 研发资产（C） | `/setup-harbor start \| stop \| status \| verify \| logs` |
| `setup-mysql` | 数据存储（A 环境级 ×5） | `/setup-mysql start --env <dev\|sit\|fat\|uat\|prod>` |
| `setup-redis` | 数据存储（A） | `/setup-redis start --env <env>` |
| `setup-mongodb` | 数据存储（A） | `/setup-mongodb start --env <env>` |
| `setup-rabbitmq` | 消息中间件（A） | `/setup-rabbitmq start --env <env>` |
| `setup-consul` | 服务治理（A） | `/setup-consul start --env <env>` |
| `setup-apollo` | 配置中心（D 合并 ×2） | `/setup-apollo start --env <nonprod\|prod>` |
| `setup-tempo` | 可观测性（B 域级 ×2） | `/setup-tempo start --env <nonprod\|prod>` |
| `setup-loki` | 可观测性（B） | `/setup-loki start --env <nonprod\|prod>` |
| `setup-prometheus` | 可观测性（B） | `/setup-prometheus start --env <nonprod\|prod>` |
| `setup-grafana` | 可观测性（B） | `/setup-grafana start --env <nonprod\|prod>` |
| `setup-otel-collector` | 可观测性（B） | `/setup-otel-collector start --env <nonprod\|prod>` |
| `setup-k3s` | 业务底座（B ×2） | `/setup-k3s start --env <nonprod\|prod>` |
| `setup-edge-nginx` | DMZ 入口（B ×2） | `/setup-edge-nginx start --env <nonprod\|prod> \| add-route --mode <public\|whitelist>` |
| `setup-gitlab-runner` | CI/CD 执行（B ×2） | `/setup-gitlab-runner start --env <nonprod\|prod> \| register \| verify \| unregister` |
| `setup-cicd` | 业务接入指导（E） | `/setup-cicd demo \| integrate`（不接受 `--env`） |

---

## 目录结构

```
tech-stack-setup/
├── CLAUDE.md                         ← AI 决策上下文（自动加载）
├── README.md                         ← 本文件
├── architecture-blueprint.md         ← 架构蓝图（最终权威）
├── references/
│   ├── README.md                     ← 文档索引、分层架构图
│   ├── deployment-principles.md      ← 核心原则、前置准备、实战经验
│   ├── network-architecture.md       ← 网络拓扑、四层域名、DNS 解析
│   ├── configuration-reference.md    ← 跨节点连接清单
│   ├── observability-pipeline.md     ← OTel 数据流、双方案接入
│   ├── request-lifecycle.md          ← 请求穿越案例
│   ├── resource-planning.md          ← 资源估算、高可用、备份
│   └── deployment-guide/             ← 五阶段 50 个 task 模板库
├── deployment-plan/                  ← 实际部署计划（动态生成产物）
├── env/                              ← 运行时密码本（禁止入 git）
└── setup-*/                          ← 20 个 skill（每个含 SKILL.md + actions/ + references/ + README.md + install.sh）
```
