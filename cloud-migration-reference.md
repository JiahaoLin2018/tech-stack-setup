# 上云参考架构（生产域自治化方案）

> **文档定位**：本文档是 `architecture-blueprint.md` 的**增量补丁**，仅适用于"生产环境部署到阿里云或其他公有云、与内网测试机房物理隔离"的场景。当前阶段（生产/测试同构、共用内网基础设施）**不实施**，仅作为未来上云时的预案保留。
>
> **核心目标**：让生产域成为真正的"物理孤岛"——在内网测试机房整体崩溃、跨域 VPN 链路失效的情况下，生产环境仍能独立运行、自我重启、被运维管控（接受发版受阻）。
>
> **不变的边界**：内部统一域名后缀仍为 `*.renew.com`；外部公网业务域名由部署方自定义。

> **与蓝图 §1.2 的对应关系**：当前架构中，全局共享层的 infra-nginx 跨网段反代生产 UI 与 `apollo-config-prod.renew.com`，**生产域内部不部署 infra-nginx**。本方案上云后**继续保持此设计**——生产 VPC 内不部署 prod-infra-nginx，全局共享层 infra-nginx 通过跨域 VPN 继续反代生产 UI。跨域 VPN 故障期接受运维短期失能（业务可用性不受影响），详见 [§4.3](#43-反代层保持内网-infra-nginx-跨域反代生产-ui不部署-prod-infra-nginx)。

---

## 目录

- [一、适用场景与触发条件](#一适用场景与触发条件)
- [二、当前架构的跨域依赖盘点](#二当前架构的跨域依赖盘点)
- [三、上云后的目标网络拓扑](#三上云后的目标网络拓扑)
- [四、改造清单](#四改造清单)
- [五、域名设计方案](#五域名设计方案)
- [六、关键风险与缓解措施](#六关键风险与缓解措施)
- [七、灾备演练 SOP](#七灾备演练-sop)
- [八、需要部署方确认的决策点](#八需要部署方确认的决策点)

---

## 一、适用场景与触发条件

### 何时启用本方案

满足以下任一条件时，应将生产域从"与测试同构"演进为"自治孤岛"：

1. 生产业务部署到阿里云 / 腾讯云 / 华为云等公有云，与内网测试机房网络物理隔离
2. 监管/合规要求生产域可独立运行（如金融行业等保三级、PCI-DSS）
3. 业务对 RTO/RPO 有明确目标（如 RTO ≤ 30min、RPO ≤ 5min）
4. 生产规模到达需要 HA 的临界点（单实例故障代价 > HA 改造成本）

### 故障场景定义

本方案以"**测试机房整体崩溃 + 跨域 VPN 链路失效**"为最坏假设，要求生产域在该状态下：

- ✅ 已运行的生产服务正常对外
- ✅ 生产 K3s 节点重启 / Pod 被驱逐重调度后能正常起来
- ✅ 运维能通过生产 VPN + 本地 kubectl 做故障定位（生产 UI 短期失能可接受）
- ✅ 告警通道可用
- ⚠️ 接受：故障期内不能发版（Apollo 配置变更、CI/CD 流水线、Nexus 拉新依赖均不可用）
- ⚠️ 接受：测试机房恢复后通过 Apollo Portal 跨网段挂载继续配置管理

---

## 二、当前架构的跨域依赖盘点

把生产域搬到公有云时，**当前蓝图里以下组件会变成致命的跨域依赖**：

| # | 依赖项 | 当前路径 | 跨域故障时影响 | 致命度 |
|---|---|---|---|---|
| 1 | DNS 解析 | 生产 K3s CoreDNS → 内网 dnsmasq | 生产 Pod 解析不到 `mysql-prod.renew.com`，业务雪崩 | 🔴 致命 |
| 2 | 镜像拉取 | 生产 K3s → 内网 Harbor | 节点重启/Pod 重调度时拉镜像失败，集群越动越烂 | 🔴 致命 |
| 3 | 配置中心 Apollo | 生产 Apollo Portal 在内网 + 业务 Pod 拉 `apollo-config-prod` 配置 | **Portal 锁死**（已运行 Pod 内存/本地缓存兜底，业务不挂）；**若 `apollo-config-prod` 走内网反代，新 Pod 启动拉不到配置 → K3s 自愈 / HPA 扩容 / 滚动更新全失败 → 业务雪崩** | 🔴 致命（仅 Config 拉取路径）|
| 4 | CI/CD | 生产 Runner → 内网 GitLab | 无法发版（可接受）| 🟡 中等 |
| 5 | Maven 依赖 | 生产 Runner → 内网 Nexus | 无法构建（可接受）| 🟡 中等 |
| 6 | 监控访问 | 内网运维 → infra-nginx → 生产 Grafana | 运维短期盲飞，可通过生产 VPN + 本地 kubectl 应急定位 | 🟡 中等 |
| 7 | 跨域链路本身 | 单条专线/VPN | 本身就是 SPOF | 🔴 致命 |

**改造的核心思路**：把上述 1、2、3（仅 Apollo Config 拉取路径）、7 这四类**生产 Pod 启动闭环必需的依赖**全部本地化到生产 VPC 内；4、5、6 与 3 中的 Portal 配置变更部分接受跨域故障时的功能受限（业务不受影响，运维通过生产 VPN + 本地 kubectl 兜底）。

> **关于第 3 项的拆分**：Apollo 在生产域有两个角色——① Portal（运维变更配置入口，可接受短期失能，已运行 Pod 用本地缓存兜底）；② Config Service（业务 Pod 启动时拉取配置）。**②的网络路径必须本地化**，否则 K3s 自带的自愈机制（节点故障重新调度、HPA 扩容、滚动更新）会在跨域 VPN 故障期全部失败，把单点故障演变为业务级雪崩。详见 [§4.1 PrivateZone 域名规划](#41-dns-层阿里云-privatezone-接管)。

---

## 三、上云后的目标网络拓扑

```
┌──────────────────────────────────────────────────────────────────────┐
│                          公网入口层                                    │
│                                                                      │
│  公网用户 ──▶ DNS解析 *.{prodPublicDomain}      ──▶ edge-nginx (prod) │
│  公网用户 ──▶ DNS解析 *.{nonprodPublicDomain}   ──▶ edge-nginx (nonp) │
└──────────────────────────────────────────────────────────────────────┘
                            │                      │
                            ▼                      ▼
┌──────────────────────────────────┐  ┌──────────────────────────────────┐
│  阿里云生产 VPC（自治孤岛）       │  │  内网测试机房                      │
│                                  │  │                                  │
│  ┌────────────────────────────┐  │  │  ┌──────────────────────────┐   │
│  │ 数据/解析层               │  │  │  │ 全局共享层                │   │
│  │  - PrivateZone            │  │  │  │  dnsmasq · infra-nginx   │   │
│  │  - ACR (镜像)             │  │  │  │  GitLab · Nexus · Harbor │   │
│  │  - RDS / Tair / MongoDB  │  │  │  │  Apollo Portal           │   │
│  └────────────────────────────┘  │  │  └──────────────────────────┘   │
│  ┌────────────────────────────┐  │  │  ┌──────────────────────────┐   │
│  │ 计算/管控层               │  │  │  │ 非生产域                  │   │
│  │  - K3s (生产)             │  │  │  │  K3s (nonprod)           │   │
│  │  - LGT 栈 (生产)          │  │  │  │  LGT 栈 (nonprod)        │   │
│  │  - K3s API Server :6443  │  │  │  │  4 套测试中间件           │   │
│  │    (VPC内网,VPN直连)     │  │  │  │  Apollo Config × 4       │   │
│  │                          │  │  │  └──────────────────────────┘   │
│  └────────────────────────────┘  │  │                                  │
│                                  │  │                                  │
│  ▲ 生产VPN (运维专用,独立通道)    │  │                                  │
└──┼───────────────────────────────┘  └──────────────────────────────────┘
   │              ▲                                ▲
   │              │ 跨域VPN(生产↔测试,日常同步)     │
   │              └────────────────────────────────┘
   │
   ▼
┌──────────────────────────────────────────────────────────────────────┐
│        阿里云独立 ECS（构建专用，不在生产 VPC 内）                     │
│                                                                      │
│   GitLab Runner (tag: prod) + 持久化 ~/.m2                           │
│   - release 分支触发构建 → 推 ACR                                    │
│   - 构建依赖：跨域VPN → 内网Nexus                                    │
│   - 跨域故障时使用 ~/.m2 本地缓存（仅旧依赖可用，新依赖需等恢复）      │
└──────────────────────────────────────────────────────────────────────┘

   告警通道（独立于内网）
   生产 Alertmanager ──▶ 公网 webhook（钉钉/飞书）
                    ──▶ 公网 SMTP（阿里云邮件推送）
```

### 三类网络通道的职责划分

| 通道 | 用途 | 故障容忍 |
|---|---|---|
| **公网** | 公网用户访问 edge-nginx；告警 webhook/SMTP | 高（多链路冗余）|
| **跨域 VPN** | Apollo Portal 跨网段挂载、Nexus 依赖拉取、监控数据查阅 | **测试机房崩 = 此通道失效（设计上接受）** |
| **生产 VPN** | 运维 → 生产 VPC 应急访问 | 阿里云原生 VPN 网关 HA，不依赖测试机房 |

---

## 四、改造清单

### P0 — 上云时必做

#### 4.1 DNS 层：阿里云 PrivateZone 接管

| 项 | 做法 |
|---|---|
| 部署 | 阿里云 PrivateZone，绑定到生产 VPC |
| 域名规划（业务必需，写入 PrivateZone）| 生产 Pod 启动闭环依赖的域名**全部直接解析到生产 VPC 内服务的内网 IP**（直连，不经任何反代）：`mysql-prod / redis-prod / mongodb-prod / rabbitmq-prod / consul-prod` 数据中间件；`otel-prod / loki-prod / tempo-prod / prometheus-prod / alertmanager-prod` 可观测性数据端口；`k3s-prod`；**`apollo-config-prod.renew.com` → 生产 Apollo Config 内网 IP（关键）** |
| 域名规划（运维 UI，**不写入 PrivateZone**）| `*-prod-ui.renew.com`（grafana / prometheus / alertmanager 等）由内网 dnsmasq 泛解析→infra-nginx 跨域反代，运维内网访问；业务 Pod 不依赖 |
| K3s CoreDNS | `.renew.com` forward 仅指向 PrivateZone（阿里云内置 DNS：`100.100.2.136` / `100.100.2.138`）；**未在 PrivateZone 注册的域名（如 `*-prod-ui`）解析失败，业务不需要不影响** |
| 同步机制 | 推荐 GitOps：维护 `prod-hosts.yaml`，CI 通过阿里云 SDK 增量同步到 PrivateZone |
| 验证 | 主动断跨域 VPN，在生产节点 `nslookup mysql-prod.renew.com` 仍正常；`kubectl rollout restart` 触发 Pod 重建，新 Pod 仍能拉取 Apollo 配置 |

**业务 Pod apollo.meta 配置变更（关键）**：

由于 `apollo-config-prod.renew.com` 上云后由 PrivateZone **直连到生产 Config Service 内网 IP**（不再走内网 infra-nginx :80 反代到 :8605），业务 Pod 的 Apollo 客户端配置必须**显式带上端口**：

| 环境 | `apollo.meta`（app.sh 注入） | 端口由谁处理 |
|------|---------------------------|------------|
| dev / sit / fat / uat（不变）| `http://apollo-config-{env}.renew.com` | 内网 infra-nginx 反代 :80 → :8605 |
| **prod（变）** | `http://apollo-config-prod.renew.com:8605` | **直连，业务必须显式写端口** |

**实施影响**：setup-gitlab-runner 的 app.sh 在 `--env prod` + 上云模式下，注入 `APOLLO_META` 时按上表区分；当前未上云阶段保持原格式。

#### 4.2 镜像层：阿里云 ACR

| 项 | 做法 |
|---|---|
| 实例 | 阿里云 ACR 企业版（开 P2P 加速 + 漏洞扫描 + 镜像签名）|
| CI 触发 | release 分支合并 / 打 `v*` tag → 触发生产构建 Pipeline |
| 推送策略 | release 分支**重新构建**推 ACR（不复用 Harbor 镜像，避免 Harbor 故障传染）|
| 镜像 tag | 强制带 git commit short SHA + release 版本号 |
| 镜像不一致风险缓解 | ① pom.xml 锁版本（不用 SNAPSHOT）<br>② Dockerfile `FROM` 写 digest（如 `eclipse-temurin@sha256:abc...`）<br>③ npm 锁 `package-lock.json`<br>④ release 镜像在 prod-staging namespace 跑 smoke test 后才切正式 |
| 跨地域复制 | 主华东 → 备华北/华南，避免单 region 故障 |
| 拉取凭证 | K3s 配置 `imagePullSecrets` 指向 ACR，所有 Deployment 引用 |

#### 4.3 反代层：保持内网 infra-nginx 跨域反代生产 UI（不部署 prod-infra-nginx）

**生产 VPC 内不部署反代 nginx**。理由如下：

| 项 | 说明 |
|---|---|
| 当前架构沿用 | 全局共享层 infra-nginx 跨网段反代 `*-prod-ui.renew.com`（运维 UI），运维内网访问生产 UI 无需额外组件 |
| **Apollo Config 例外** | `apollo-config-prod.renew.com` 上云后**不再走内网反代**，由生产 PrivateZone 直接解析到生产 Apollo Config 内网 IP（[§4.1](#41-dns-层阿里云-privatezone-接管)），业务 Pod 直连 `:8605`，**不依赖跨域 VPN**——这是业务启动闭环的硬要求 |
| 跨域 VPN 故障期 | 接受运维短期内无法访问生产 UI（Grafana / Prometheus UI / Alertmanager UI / Apollo Portal 配置变更入口）；业务可用性不受影响（含 Pod 重建、HPA 扩容、节点自愈，因 Apollo Config 已 PrivateZone 直连）|
| 业务影响 | 无 — 业务 Pod 不依赖 infra-nginx，仅依赖 PrivateZone 解析与 ACR 镜像 |
| 应急通道 | 运维通过生产 VPN + 本地 kubectl 直连 K3s API Server（[§4.5](#45-运维-kubectl-入口本地-kubectl--生产-vpn不部署-jumpbox)）仍可执行 `kubectl get/logs/exec` 做故障定位 |

> **设计原则（KISS）**：业务可用性优先。VPN 故障期短期失能可观测性是可接受的折中，不为低概率事件部署额外组件。

#### 4.4 计算层：生产 Release Runner（独立 ECS）

| 项 | 做法 |
|---|---|
| 位置 | 阿里云独立 ECS，**不在生产 VPC 内**，避免构建机污染生产网络 |
| 注册 | 注册到内网 GitLab，打上 `tag: prod` |
| Maven 依赖 | ECS 数据盘持久化挂载 `~/.m2`，热依赖本地命中；冷依赖走跨域 VPN 拉内网 Nexus |
| Docker 缓存 | 数据盘持久化 `/var/lib/docker`，加快重复构建 |
| 跨域 VPN 故障容忍 | 旧依赖本地缓存命中可继续构建；新依赖等 VPN 恢复（接受）|

#### 4.5 运维 kubectl 入口：本地 kubectl + 生产 VPN（不部署 jumpbox）

**生产 VPC 内不部署独立 jumpbox / bastion ECS**。理由如下：

| 项 | 说明 |
|---|---|
| K3s API Server 入口 | 生产 K3s API Server (`:6443`) 暴露在生产 VPC 内网（不挂公网，由 VPC 安全组限制源 IP）|
| 运维操作方式 | 运维**本地装 kubectl + 客户端证书**，通过生产 VPN 接入 VPC 后直接访问 `:6443`，无需 SSH 中转 |
| 应急救火 | 跨域 VPN + Runner 全失效时，运维本地直接 `kubectl set image / rollout restart`，操作链路与日常一致 |
| 审计 | K3s API Server 自身审计日志（`--audit-log-path`）+ 阿里云 ActionTrail（VPC 流量），无需 jumpbox 二级日志 |
| 极端兜底 | 生产 VPN 也失效时，启用 [§4.10](#410-生产-vpn-高可用) 公网堡垒（仅 IP 白名单 SSH，与传统 jumpbox 等效） |

> **设计原则（KISS）**：避免重复中转层。本地 kubectl + VPN 直连是云原生最佳实践（零信任 + RBAC 鉴权），比"SSH→jumpbox→kubectl"少一跳，攻击面更小。

#### 4.6 网络通道：双 VPN

| 通道 | 实现 | 用途 |
|---|---|---|
| 跨域 VPN | 阿里云 VPN 网关 ←→ 内网 IPSec 设备 | 日常 Apollo Portal 跨域、Nexus 拉取、监控数据查阅 |
| 生产 VPN | 阿里云 VPN 网关，独立 IP | 运维 → 生产 VPC 应急访问 |

**强制要求**：跨域 VPN 故障**不能影响**生产 VPN 可用性，两者必须是**独立网关 + 独立证书**。

> 不部署"公网备线 VPN"：跨域 VPN 故障期（通常数小时内）短期失能 Apollo Portal / Nexus / 生产 UI 是可接受的，业务不受影响（已运行 Pod 用 Apollo Client 本地缓存兜底）。

#### 4.7 告警通道

| 通道 | 优先级 | 触发场景 |
|---|---|---|
| 钉钉/飞书/企业微信机器人（公网 webhook）| 主 | 所有 P0/P1 告警 |
| 阿里云邮件推送（公网 SMTP）| 备 | P0 告警双发 |
| 阿里云短信（可选）| 兜底 | 仅 critical 级别（生产 K3s 全挂、MySQL 连不上等）|

Alertmanager 配置 multi-route，**关键告警至少走两条独立通道**，避免单一供应商故障导致告警丢失。

---

### P1 — 上线后 1 个月内补齐

#### 4.8 数据层：阿里云托管中间件（强烈推荐）

| 组件 | 推荐替换 | 理由 |
|---|---|---|
| MySQL | RDS MySQL 高可用版 | HA + 跨 AZ + 自动备份 + 时间点恢复 |
| Redis | Tair / 云 Redis 企业版 | HA + 持久化 + 监控 |
| MongoDB | 云数据库 MongoDB | 副本集 + 自动备份 |
| RabbitMQ | 自建保留 / 消息队列 RabbitMQ 版 | 看团队接受度 |
| Consul | 自建保留 / MSE Nacos | 服务发现可保留自建 |
| Apollo MySQL | RDS MySQL 入门版 | 容量小，成本可控 |

**保留自建的唯一理由**：监管要求"业务数据不能交给云厂商"——既然已上阿里云，这条已不成立。

**渐进策略**：可以先 P0 全部用 Docker Compose 单实例上线，业务跑稳后再分批切 RDS / Tair。

#### 4.9 备份与跨地域容灾

| 组件 | 备份策略 | 异地存储 |
|---|---|---|
| RDS MySQL | 自动每日全量 + binlog 实时 | OSS 跨地域备份 |
| MongoDB（自建/云） | 每日 mongodump | OSS |
| Redis（如有持久化数据）| RDB → OSS | OSS |
| ACR | 跨地域复制 | 多 region |
| K3s etcd | 每小时备份 | OSS |
| Apollo MySQL | 每日全量 | OSS |

#### 4.10 生产 VPN 高可用

- 阿里云 VPN 网关**单线即可**（SLA 99.95% 已满足业务可用性要求；业务不依赖运维通道）
- **公网堡垒兜底**（生产 VPC 内仅 IP 白名单的 SSH 跳板，仅在生产 VPN 也挂的极端场景启用）
- 客户端 Profile 统一管理（OpenVPN / WireGuard）
- 至少 2 个独立运维账号，避免单管理员离岗即抓瞎

> 不强制双线 HA：业务可用性不依赖运维通道（生产 K3s 自治 + 自动重启），运维短期失能可通过公网堡垒兜底。

---

### P2 — 持续优化

- **HA 演进**：MySQL 主从 → MGR/RDS 集群版；Redis 主从 → Sentinel/Cluster；K3s 单 control plane → 3 节点
- **密钥管理**：HashiCorp Vault 或阿里云 KMS，逐步替换 `.env` 明文密码
- **WAF / DDoS 防护**：edge-nginx (prod) 上挂阿里云 Web 应用防火墙 + DDoS 高防包
- **审计**：阿里云 ActionTrail + 自建审计日志归档到 OSS

---

## 五、域名设计方案

### 设计原则

> 内部域名永远不走公网 DNS；公网域名永远不进内部解析。

### 三类域名职责

| 类别 | 命名规范 | 示例 | 解析路径 |
|---|---|---|---|
| ① 公网生产业务 | `*.{prodPublicDomain}`（部署方自定义）| `*.api.example.com`、`pay.example.com` | 公网 DNS（推荐阿里云解析）→ edge-nginx (prod) → K3s |
| ② 公网测试业务 | `*.{nonprodPublicDomain}`（部署方自定义）| `*.fat.api.example-uat.com` | 公网 DNS → edge-nginx (nonprod) → K3s |
| ③ 内部统一域名 | `*.renew.com`（保持不变）| `mysql-prod.renew.com`、`grafana-prod-ui.renew.com` | 生产 Pod → PrivateZone；测试 Pod → 内网 dnsmasq |

### 公网域名拆分的好处（即使内部统一也建议）

1. **SSL 证书隔离**：生产 EV/付费 wildcard，测试 Let's Encrypt
2. **DNS 服务商隔离**：生产用阿里云解析，测试可用 DNSPod / Cloudflare
3. **Cookie / Session 自动隔离**：浏览器不会跨主域携带
4. **SEO 隔离**：测试域永远不会被收录污染品牌
5. **备案合规**：生产域主体清晰，测试域可灵活
6. **运维误操作隔离**：DNS 改错只能影响同一主域

### 内部域名继续 `*.renew.com` 的代价与缓解

- ⚠️ 同一域名既出现在公网 DNS（如 `*.{env}.web.renew.com`）又出现在内部 DNS（如 `mysql-prod.renew.com`）→ 存在认知混淆和潜在 DNS 投毒风险
- ✅ 缓解：上云时把"公网解析的业务域"迁到独立公网主域，`*.renew.com` 只保留为内部域名 → 公网 DNS 上不再有 `renew.com` 的 A 记录，从根本上消除双重身份

---

## 六、关键风险与缓解措施

### 风险 1：release 分支重新构建 ≠ UAT 测试通过的镜像

**风险**：UAT 测试用的是 Harbor 镜像，生产部署用的是 ACR 镜像（两次独立构建），理论上字节不一致。

**缓解**：
1. pom.xml / package.json **全部锁版本**（禁用 SNAPSHOT 和 LATEST）
2. Dockerfile 的 `FROM` 写 digest 不写 mutable tag
3. release 镜像构建出来后，**先在生产 K3s 的 prod-staging namespace 跑完整 smoke test**，通过才切到 prod namespace
4. 如做不到上述任一条，建议改回"UAT 通过后 retag 推 ACR"策略

### 风险 2：生产 VPN 是运维侧 SPOF

**风险**：测试机房崩了 + 跨域 VPN 不可用时，运维只剩生产 VPN 一条路。

**缓解**：
1. 阿里云 VPN 网关 HA（双线 / 跨 AZ）
2. 至少 2 个独立运维账号
3. 季度演练（见第七节）
4. **公网堡垒兜底**：生产 VPC 内可保留一个仅 IP 白名单的公网 SSH 跳板（仅用于"生产 VPN 也挂了"的极端场景）

### 风险 3：跨域 VPN 故障时配置无法变更

**风险**：Apollo Portal 在内网，跨域 VPN 挂了无法变更生产配置。

**已确认接受**：故障期内不发版、不改配置；已运行 Pod 用 Apollo Client 本地缓存兜底。

**强制要求**：
1. 所有生产 Pod 必须启用 Apollo Client 本地缓存 + 文件备份（`apollo.cache-dir`）
2. 配置变更前先在 UAT 验证

### 风险 4：Nexus 跨域依赖

**风险**：生产 Runner 在阿里云独立 ECS，构建依赖跨域 VPN 拉内网 Nexus。

**已确认接受**：测试机房崩了不发版，故障期不能构建是可接受的。

**缓解**：
1. ECS 数据盘持久化 `~/.m2`，热依赖本地命中
2. 关键 release 前预热依赖（提前跑一次构建拉满缓存）

### 风险 5：单一公有云供应商锁定

**风险**：阿里云区域级故障（虽极少但有先例），生产域全停。

**缓解（远期）**：
- ACR 跨地域复制、RDS 跨地域备份已能保住数据
- 真要做多云容灾，需引入第二朵云（成本翻倍，按业务体量判断）

---

## 七、灾备演练 SOP

**频率**：上线后 1 次（验收）+ 每年 1 次（复审），每次 ≤ 4 小时。

> 不采用季度演练：业务不依赖跨域 VPN，年度演练已足够验证生产域自治能力，避免频繁演练对小团队的成本压力。

### 演练步骤

```
准备阶段：
  1. 通知干系人（业务/运维/管理层）
  2. 确认告警通道收件人就位
  3. 准备演练记录模板

执行阶段：
  1. 主动在防火墙断跨域 VPN（保留生产 VPN）
  2. 等待 5 分钟，观察告警是否正常触发并送达

  3. 验证生产域自治：
     ├─ [ ] 生产 PrivateZone 解析 `mysql-prod.renew.com` 正常
     ├─ [ ] 重启 1 个生产 Pod，验证从 ACR 拉镜像成功
     ├─ [ ] 杀掉 1 个生产 Pod，验证 K3s 自愈成功
     ├─ [ ] 跨域 VPN 故障期 grafana-prod-ui 短期不可访问（已接受）
     ├─ [ ] 运维通过生产 VPN + 本地 kubectl 执行 `kubectl get pods` 正常
     ├─ [ ] 生产 VPN 失效演练：启用公网堡垒（IP 白名单 SSH）能进入 VPC 并 kubectl get nodes
     ├─ [ ] 告警通过钉钉 + 邮件双通道送达

  4. 验证业务连续性：
     ├─ [ ] 公网用户访问业务 API 正常
     ├─ [ ] 数据库读写正常
     ├─ [ ] 消息队列消费正常

恢复阶段：
  5. 防火墙恢复跨域 VPN
  6. 验证 Apollo Portal 跨网段挂载恢复
  7. 验证 Runner 重新连上 GitLab
  8. 撰写演练报告，归档问题清单
```

### 演练失败的处理

任一项失败即视为演练失败，必须：
1. 立即恢复跨域 VPN
2. 定位根因
3. 修复并重测
4. 通过前不能视为生产域具备自治能力

---

## 八、需要部署方确认的决策点

实施本方案前，部署方需明确以下选择：

### 8.1 公网域名

| 项 | 决策 |
|---|---|
| 公网生产主域 | _______________（部署时填写）|
| 公网测试主域 | _______________（部署时填写）|
| 内部域名后缀 | `*.renew.com`（已确认不变）|

### 8.2 数据层方案

| 组件 | 选项 | 默认推荐 |
|---|---|---|
| MySQL | 自建 / RDS 高可用 | RDS 高可用 |
| Redis | 自建 / Tair / 云 Redis | Tair |
| MongoDB | 自建 / 云 MongoDB | 云 MongoDB |
| RabbitMQ | 自建 / 消息队列 RabbitMQ 版 | 自建（团队熟）|
| Consul | 自建 / MSE Nacos | 自建 |

### 8.3 镜像构建策略

| 项 | 选项 | 默认 |
|---|---|---|
| ACR 推送 | release 重新构建 / UAT 镜像 retag | release 重新构建（已确认）|
| 镜像锁定 | pom.xml 锁版本 + Dockerfile digest | 强制要求 |
| 跨地域复制 | 开 / 不开 | 开 |

### 8.4 网络通道

| 项 | 选项 | 默认 |
|---|---|---|
| 跨域 VPN 备线 | 公网 IPSec / 不要 | 不要（接受 VPN 故障期短期失能） |
| 生产 VPN | 单网关 / 双线 HA | 单网关（业务不依赖运维通道，单点 SLA 99.95% 已足够） |
| 公网应急堡垒 | 启用 / 不启用 | 启用（仅极端情况）|

### 8.5 告警通道

| 通道 | 启用 | 默认 |
|---|---|---|
| 钉钉/飞书机器人 | ☐ | 必选 |
| 公网 SMTP 邮件 | ☐ | 必选 |
| 阿里云短信 | ☐ | 仅 critical |

---

## 附录 A：当前架构 vs 上云架构对照表

| 组件 | 当前架构 | 上云后 |
|---|---|---|
| DNS | 内网 dnsmasq + hosts.lan | 内网 dnsmasq（测试用）+ 阿里云 PrivateZone（生产用）|
| 反代 | 单一 infra-nginx | 单一 infra-nginx（内网，跨域反代生产 UI 不变；不在生产 VPC 内部署反代） |
| 镜像仓库 | 单一 Harbor | Harbor（测试用）+ ACR（生产用，跨地域复制）|
| MySQL | 单实例 Docker Compose × 5 | 测试 4 套自建 + 生产 RDS 高可用 |
| Redis | 单实例 Docker Compose × 5 | 测试 4 套自建 + 生产 Tair |
| Apollo | nonprod 10 容器 + prod 3 容器 | 同左，prod MySQL 切 RDS |
| K3s | 2 套（nonprod + prod）| 同左，但生产在阿里云 |
| LGT 栈 | 2 套（nonprod + prod）| 同左 |
| GitLab Runner | 2 套（nonprod + prod）| nonprod 内网 + **prod 独立阿里云 ECS** |
| edge-nginx | 2 套（nonprod + prod）| 同左 |
| 跨域链路 | 无 | 跨域 VPN（生产↔测试）+ 生产 VPN（运维↔生产）|

## 附录 B：上云后增量部署的 Skill 清单

> 本节列出"在现有 setup-* skill 之外"额外需要的部署动作。

| Skill / 动作 | 内容 | 部署位置 |
|---|---|---|
| 阿里云 PrivateZone 配置 | 通过阿里云控制台/Terraform 配置 PrivateZone 解析 | 阿里云生产 VPC |
| 阿里云 ACR 配置 | 创建 ACR 企业版实例、配置访问凭证、启用跨地域复制 | 阿里云 |
| 阿里云 RDS / Tair 配置 | 替换自建 MySQL / Redis | 阿里云生产 VPC |
| `setup-gitlab-runner --env prod-cloud`（新增）| 阿里云独立 ECS 部署 Runner，持久化 ~/.m2 | 阿里云独立 ECS |
| 公网堡垒部署（极端兜底）| 生产 VPC 内独立 ECS，仅 IP 白名单 SSH，平时禁用 | 阿里云生产 VPC |
| 运维 kubectl 配置 | 本地装 kubectl + 客户端证书 + kubeconfig 指向 K3s API Server `:6443` | 运维终端 |
| VPN 网关配置 | 跨域 VPN + 生产 VPN | 阿里云 + 内网防火墙 |

---

## 版本历史

| 版本 | 日期 | 变更 |
|---|---|---|
| 0.5.0 | 2026-04-28 | 修正业务启动闭环关键风险：`apollo-config-prod.renew.com` 上云后必须由 PrivateZone 直连到生产 Apollo Config 内网 IP（不走内网反代），否则跨域 VPN 故障 → Pod 重建/HPA/自愈全失败 → 业务雪崩；§二风险盘点第 3 项细化为 Portal（可接受）+ Config 拉取（致命）两个层面；§4.1 PrivateZone 域名规划区分"业务必需直连"与"运维 UI 不入 PrivateZone"，新增 `apollo.meta=http://apollo-config-prod.renew.com:8605`（业务 Pod 必须显式带端口）；§4.3 增加 Apollo Config 例外说明 |
| 0.4.0 | 2026-04-27 | 进一步 KISS：删除应急 jumpbox（运维改用本地 kubectl + 生产 VPN 直连 K3s API Server），§4.5 反转为"为何不部署 jumpbox"，§三拓扑图 jumpbox 节点替换为 K3s API Server；公网堡垒（§4.10）作为生产 VPN 失效的极端兜底（与传统 jumpbox 等效） |
| 0.3.0 | 2026-04-27 | KISS 简化：删除 prod-infra-nginx（接受 VPN 故障期生产 UI 短期不可访问）；删除公网备线 VPN；生产 VPN 从双线 HA 降级为单线 + 公网堡垒兜底；灾备演练从季度降级为年度 + 上线 1 次；§4.3 反转为"为何不部署 prod-infra-nginx"；§二风险 6 等级 🟠→🟡 |
| 0.2.0 | 2026-04-27 | 对齐 architecture-blueprint.md 1.9.0：呼应蓝图 §1.2 的全局 infra-nginx 跨域反代职责；§4.3 prod-infra-nginx 反代清单补充 `apollo-config-prod.renew.com` |
| 0.1.0 | 2026-04-27 | 初稿：基于 architecture-blueprint.md 1.8.0 + 跨域故障专题讨论结论整理 |
