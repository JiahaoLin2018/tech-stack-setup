# 参考文档索引

本目录是 Tech Stack Setup 的全套架构与运维参考文档。

> 架构权威是项目根目录的 [architecture-blueprint.md](../architecture-blueprint.md)（v1.9.0）。本目录文档是其分主题的详细阐述与运维落地。

---

## 文档索引

| 文档 | 内容 | 适合谁读 |
|------|------|---------|
| [部署原则](deployment-principles.md) | 核心原则、规划流程、前置准备（Docker / 内核 / 镜像 / 配置上传 / Exporter 用户 / 密码生成）、版本兼容踩坑 | 运维 / 部署启动 |
| [网络架构](network-architecture.md) | 四层域名规范、hosts.lan 必备 37 条、DNS 解析机制、双入口流量路径、多环境 DNS 解析对照 | 网络设计 / 排障 |
| [配置参考](configuration-reference.md) | 跨节点连接清单（按 ABCDE 五类 skill 分组）、服务访问方式总表、多环境配置差异、env→domainEnv 映射 | 配置管理 |
| [可观测性数据流](observability-pipeline.md) | OTel→Tempo/Loki/Prometheus 完整数据流、env 标签注入主通路、Spring Boot 双方案接入、告警流程 | 监控架构 / 排障 |
| [请求生命周期](request-lifecycle.md) | "用户申请贷款"案例（PROD 视角）+ nonprod / prod 数据隔离演示 + 服务参与总结 | 新人入门 / 理解全貌 |
| [资源规划](resource-planning.md) | 单实例资源建议（按五类 skill）、高可用演进路径、备份策略、部署模式说明 | 容量评估 / 生产规划 |
| [K3s 资源协作](k3s-routing-guide.md) | K3s 内 Deployment / Pod / Service / IngressRoute / Traefik 角色比喻 + 完整路由链路 | K3s 新人 |
| [部署指南模板库](deployment-guide/) | 五阶段 21 个 task 模板（按 architecture-blueprint.md 第五部分），按用户环境填充具体 IP 后生成 deployment-plan/ | 实际部署 |

---

## 架构分层（对照蓝图三大域）

```
┌─────────────────────────────────────────────────────────────────────┐
│  全局共享层（Global Internal Zone，C 类，1 套）                        │
│    setup-dns · setup-infra-nginx · setup-gitlab · setup-nexus       │
│    · setup-harbor                                                    │
│  跨所有环境共享，传入 --env 即报错退出                                 │
├─────────────────────────────────────────────────────────────────────┤
│  非生产域 NonProd                       生产域 Prod（物理孤岛）        │
│  ┌────────────────────────────┐        ┌────────────────────────────┐│
│  │ B 类共用底座（1 套）:        │        │ B 类独立底座（1 套）:        ││
│  │  K3s + LGT + GitLab Runner  │        │  K3s + LGT + GitLab Runner  ││
│  │  + edge-nginx (DMZ nonprod) │        │  + edge-nginx (DMZ prod)    ││
│  │                             │        │                             ││
│  │ D 类 Apollo（10 容器）:      │        │ D 类 Apollo（3 容器）:       ││
│  │  Portal+MySQL+4 Config/Admin│        │  Config+Admin+独立 MySQL    ││
│  │                             │        │                             ││
│  │ A 类环境级独立（4 套）:       │        │ A 类环境级独立（1 套）:       ││
│  │  MySQL × 4 + Redis × 4 +    │        │  MySQL × 1 + Redis × 1 +    ││
│  │  MongoDB × 4 + RabbitMQ × 4 │        │  MongoDB × 1 + RabbitMQ × 1 ││
│  │  + Consul × 4               │        │  + Consul × 1               ││
│  │ Dev / SIT / FAT / UAT       │        │ Prod                        ││
│  └────────────────────────────┘        └────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
```

> **设计理念**：每一层只依赖下面的层；DNS 是最底层基础设施（架构基石），必须最先部署；全局共享层被 nonprod / prod 两个域共同依赖；非生产域 4 环境共用底座但通过 Namespace + LGT env 标签逻辑隔离；生产域物理孤岛，与非生产无任何硬件 / 网络 / 数据交集；所有中间件 / LGT / Apollo / Runner 全部在 K3s **外部** Docker Compose 部署，K3s 仅作业务运行底座。

### 流量入口分层

| 流量类型 | 入口 | 路径 |
|---------|------|------|
| **公网业务流量** | edge-nginx (DMZ 双实例) | `*.{env}.{web\|api}.renew.com` → edge-nginx HTTPS → k3s-{nonprod\|prod}.renew.com:8083 → Pod |
| **内部管理流量** | infra-nginx :80 | 浏览器 → 各管理 UI（Grafana / GitLab / Harbor / Apollo / Consul / RabbitMQ 等） |
| **内网业务流量** | infra-nginx :80 | 业务域名按 nonprod / prod 双 K3s 分流（与公网到 Traefik 入口一致） |
| **微服务直连基础设施** | DNS 直连，不经过 Nginx | Pod → CoreDNS → dnsmasq → hosts.lan → 直连数据端口 |
| **TCP 透传** | infra-nginx stream 块 | GitLab SSH `:2222` / Nexus Docker `:8082` |

---

## 各服务解决什么问题

### 全局共享层 — 网络基座 + 研发资产

| 服务 | 解决的问题 |
|------|-----------|
| **dnsmasq** | 局域网 `*.renew.com` 域名解析（架构基石，最先部署） |
| **infra-nginx** | 内部 Web UI 统一反代入口 + GitLab SSH / Nexus Docker TCP 透传 + 业务域名内网直达 K3s |
| **GitLab EE** | 代码托管 + CI/CD 流水线（含许可证激活）|
| **Nexus 3 OSS** | Maven 私有仓库 + Docker Registry |
| **Harbor 2.12** | Docker 镜像仓库 + Trivy 漏洞扫描 |

### 环境级独立层 — 业务数据持久化（每环境独立实例）

| 服务 | 解决的问题 | 典型使用场景 |
|------|-----------|------------|
| **MySQL 8.4** | 关系型数据，事务保证 | 用户表 / 订单表 / 账户余额 |
| **Redis 8.0** | 亚毫秒延迟 / 原子操作 | Session / 接口限流 / 分布式锁 / 热点缓存 |
| **MongoDB 8.0** | 灵活 Schema / 文档存储 | 风控规则文档 / 审批流程记录 / 日志归档 |
| **RabbitMQ 4.0** | 服务间异步通信 / 削峰填谷 | 通知事件 / 异步任务 |
| **Consul 1.20** | 服务实例动态注册与发现 | 微服务互相调用，不依赖硬编码 IP；作为 Prometheus consul_sd 源 |

### 域级共用层 — 业务底座 + 可观测性 + CI/CD（nonprod 共用 + prod 独立）

| 服务 | 解决的问题 |
|------|-----------|
| **K3s v1.32** | 业务应用编排（前端 / Gateway / Spring Boot 微服务）；自动扩缩容 / 故障自愈 / 滚动更新 |
| **OTel Collector 0.120** | Traces / Logs 统一接收网关，应用只对接一个 OTLP 端点 |
| **Tempo 2.7** | 分布式链路追踪（"这个请求慢在哪一步？"）|
| **Loki 3.5** | 日志聚合查询（"这个错误什么时候开始？"），OTLP 原生接收 |
| **Prometheus v3.2** | 指标采集 + 告警（"CPU 飙了？QPS 多少？"）；consul_sd 自动发现服务 |
| **Alertmanager v0.28** | 告警去重 / 分组 / 路由（钉钉 / 邮件 / Slack）|
| **Grafana 11.4** | 统一可视化看板（Trace ↔ Log ↔ Metrics 三向跳转，$env 模板变量切换）|
| **GitLab Runner 17.8** | CI/CD 执行器 + CI Job 执行环境一站式部署（含 OTel Java Agent）|
| **edge-nginx 1.27** | 公网业务流量入口（DMZ 双实例物理隔离），HTTPS / 限流 / IP 白名单 |

### 配置中心 — 合并部署（D 类）

| 服务 | 解决的问题 |
|------|-----------|
| **Apollo 2.5.0** | 运行时动态修改配置无需重启；nonprod 一次拉起 10 容器 + prod 一次拉起 3 容器；内置专用 MySQL（与业务 MySQL 完全分离）|

### 业务接入指导 — 不部署基础设施（E 类）

| 服务 | 解决的问题 |
|------|-----------|
| **setup-cicd** | demo 端到端验证 CI/CD 链路 + integrate.md 业务接入指南（双方案 + 关闭 OTel 三套示例） |

---

## 设计决策记录

> 完整决策与论证见 [architecture-blueprint.md](../architecture-blueprint.md)。

### 为什么 K3s + Docker Compose 混合架构？

| 层级 | 部署方式 | 原因 |
|------|---------|------|
| 业务应用层（前端 / Gateway / 微服务）| **K3s** | 自动扩缩容（HPA）/ 故障自愈 / 滚动更新 / 多实例负载均衡 |
| 基础设施层（中间件 / LGT / Apollo / GitLab Runner）| **Docker Compose** | 运维边界清晰，与业务生命周期解耦；中间件不适合频繁滚动；LGT 需独立资源 |

### 为什么三大逻辑域分离？

| 域 | 原因 |
|----|------|
| 全局共享层 | GitLab / Nexus / Harbor 是研发资产，跨所有环境共享；DNS / infra-nginx 是网络基座 |
| 非生产域（4 环境共用）| 节省资源；通过 K8s Namespace + LGT env 标签实现逻辑隔离 |
| 生产域（物理孤岛）| FinTech 合规要求；与非生产无任何硬件 / 网络 / 数据交集 |

### 为什么选 OTel + Tempo 而不是 SkyWalking？

| 维度 | SkyWalking | OTel + Tempo |
|------|-----------|-------------|
| 标准化 | 私有协议 | OpenTelemetry 开放标准 |
| 存储成本 | 依赖 ES（内存大户）| Tempo 无索引架构，存储仅需 Parquet |
| 生态集成 | 独立 UI | Grafana 统一看板，Trace ↔ Log ↔ Metrics 关联 |
| Spring Boot 3 支持 | 需要 Agent | Micrometer Tracing 原生集成（方案 A） |

### 为什么选 Loki 而不是 ELK？

| 维度 | ELK Stack | Loki |
|------|----------|------|
| 内存占用 | ES 需要 4-8 GB+ | Loki 仅 1 GB |
| 索引策略 | 全文索引（昂贵）| 仅索引标签（低成本）|
| 查询方式 | KQL | LogQL（类 PromQL，学习成本低）|
| 与 Grafana 集成 | Kibana 独立 UI | Grafana 原生支持，Log ↔ Trace 关联 |
| OTLP 支持 | 需 Logstash 插件 | 3.5+ 原生 OTLP 接收（`/otlp` 端点）|

### 为什么 Apollo 合并部署？

| 决策 | 结论 |
|------|------|
| 一次到位拉起 | nonprod 一个 Compose 拉起 10 容器（MySQL+Portal+4×Config/Admin），prod 一个 Compose 拉起 3 容器 |
| Apollo MySQL 内置 | 由 setup-apollo 自带，与业务 MySQL（setup-mysql ×5）完全分离，避免 MySQL/应用拆成两步部署的协调成本 |

### 为什么 Metrics 不走 OTLP？

| 决策 | 结论 |
|------|------|
| 强制设置 | `OTEL_METRICS_EXPORTER=none`（方案 B 还加 `OTEL_INSTRUMENTATION_MICROMETER_ENABLED=false`）|
| 通路 | Metrics 由 Prometheus 拉取 `/actuator/prometheus`（Micrometer 产出），与 Traces/Logs 通路完全解耦 |
| 原因 | Pull 模式更可靠（应用 OOM 重启不丢数据）；避免 OTLP + Micrometer 重复导出指标 |

### 为什么 Grafana 独立为单独 skill？

数据采集（Prometheus）和数据展示（Grafana）是不同关注点：

1. **职责清晰** — 采集与可视化解耦
2. **生命周期独立** — 升级 Grafana 不需要重启 Prometheus
3. **一致性** — 与 OTel Collector / Tempo / Loki 保持同样的独立 skill 粒度

---

## 文档维护原则

- **正向描述**：所有文档只写"现在该怎么做"，禁止演进史 / 新旧对比 / 复查痕迹
- **踩坑沉淀**：部署 / 运维过程中遇到的问题统一写入对应 skill 的 `references/pitfalls.md`，不污染本目录文档
- **路由权威**：架构权威是 [architecture-blueprint.md](../architecture-blueprint.md)；本目录文档是其分主题的运维落地
- **去重**：CLAUDE.md 是 AI 决策上下文（含服务注册表 / 跨服务配置绑定）；本目录提供详细原理与流程，避免与 CLAUDE.md 重复
