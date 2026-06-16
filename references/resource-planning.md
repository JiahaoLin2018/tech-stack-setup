# 资源规划

> **本文档定位**：资源估算、高可用演进路径、备份策略、部署模式说明。
> 部署原则见 [部署原则](deployment-principles.md)；架构权威见 [architecture-blueprint.md](../architecture-blueprint.md)。

---

## 单实例资源建议

下表为各组件**单实例**最低资源需求（Docker 默认内存 limit / 业务可调）。多环境部署需按实例数倍数估算。

| 分层 | 服务 | 部署次数 | 单实例内存 | 单实例 CPU | 备注 |
|------|------|---------|-----------|-----------|------|
| **全局共享层（C 类，1 套）** ||||||
| DNS | dnsmasq | × 1 | 64-128 MB | 0.1 核 | host 网络模式，实际占用 ~5 MB |
| 内部入口 | infra-nginx | × 1 | 128 MB | 0.5 核 | host 网络模式 |
| 研发支撑 | GitLab EE | × 1 | 4-8 GB | 2-4 核 | 容器 limit 默认 4g，宿主机预留 4 GB |
| 研发支撑 | Nexus 3 | × 1 | 4-6 GB | 2-4 核 | JVM heap + DirectMemory |
| 研发支撑 | Harbor 2.12 | × 1 | 2-4 GB | 1-2 核 | 多组件（core/jobservice/portal/nginx）|
| **环境级独立层（A 类，5 套）** ||||||
| 数据存储 | MySQL（业务）| × 5 | 1-4 GB（dev/sit 1g, fat/uat 2g, prod 4g） | 1-4 核 | 含 mysqld_exporter sidecar；InnoDB Buffer = 内存 70% |
| 数据存储 | Redis | × 5 | 1-4 GB | 1-2 核 | 含 redis_exporter sidecar；maxmemory ≈ 容器内存 50% |
| 数据存储 | MongoDB | × 5 | 1-4 GB | 1-2 核 | 含 mongodb_exporter sidecar；WiredTiger Cache = 容器内存 50% |
| 消息中间件 | RabbitMQ | × 5 | 512 MB-2 GB | 1-2 核 | 内置 rabbitmq_prometheus 插件无独立 exporter |
| 服务治理 | Consul | × 5 | 256-512 MB | 0.5-1 核 | 单节点模式；prod 必须 ACL + Gossip 加密 |
| **域级共用层（B 类，2 套）** ||||||
| 业务底座 | K3s（含 Traefik）| × 2 | 1-8 GB | 1-4 核 | nonprod 共用 4 Namespace；prod 独立；按业务 Pod 规模扩展 |
| 可观测性 | OTel Collector | × 2 | 512 MB | 1 核 | bridge 网络 |
| 可观测性 | Tempo | × 2 | 2 GB | 1-2 核 | 链路数据存储 |
| 可观测性 | Loki | × 2 | 1 GB | 1-2 核 | 日志存储 |
| 可观测性 | Prometheus + Alertmanager | × 2 | 2 GB + 256 MB | 1-2 核 | 同 Compose 部署 |
| 可观测性 | Grafana | × 2 | 512 MB | 0.5-1 核 | bridge 网络 |
| 研发支撑 | GitLab Runner（含 CI Job 环境）| × 2 | 4 GB+ | 2-4 核 | 按 RUNNER_CONCURRENT 与 Pipeline 并发量扩展 |
| 接入层 | edge-nginx | × 2 | 1 GB | 1 核 | DMZ 独立机房；host 网络 |
| **D 类合并部署** ||||||
| 服务治理 | Apollo nonprod | × 1（10 容器）| 10 GB+ | 4 核+ | 1 MySQL（≈2g）+ 1 Portal（≈1g）+ 4 Config（≈1g 每个）+ 4 Admin（≈1g 每个）|
| 服务治理 | Apollo prod | × 1（3 容器）| 4 GB+ | 2 核+ | 1 MySQL（独立物理实例）+ 1 Config + 1 Admin |

> **总计单环境最小内存预算**（参考）：
> - 全局共享层 ≈ 16 GB（GitLab + Nexus + Harbor + DNS + infra-nginx）
> - 非生产域 ≈ 28 GB（4 环境 × 5 中间件 + K3s + LGT + Runner + Apollo nonprod）
> - 生产域 ≈ 24 GB（5 中间件 + K3s + LGT + Runner + Apollo prod）
> - DMZ 双 edge-nginx ≈ 2 GB
> - **完整最小生产部署约 70 GB**，业务 Pod 规模另算

---

## 部署模式说明

各数据服务（MySQL / Redis / MongoDB / RabbitMQ / Consul）的部署模式（单节点 / 主从 / 集群）由对应 Skill 在执行时决定：

1. 用户执行 `/setup-mysql start --env <env>` 时，Skill 会按当前 actions 流程部署
2. 当前实现：**5 套环境全部为单节点 Docker Compose 部署**（与生产保持一致，确保部署流程统一、快速交付）
3. 后续高可用模式（主从 / 副本集 / Cluster）按需扩展，实现于各 skill 的 `actions/`
4. `references/deployment-guide/` 中的 task 标注"支持的部署模式"和推荐选择
5. 用户生成实际部署计划时，可在 task 级别调整部署模式

> 本文档只列出"有哪些高可用选项"和"资源需求差异"，具体实现方案见各 Skill 的 SKILL.md 和 actions/。

---

## 高可用演进路径（可选）

> **当前默认部署为单节点架构**，适合中小规模场景。后续按业务量级增长可逐步演进为高可用模式。架构蓝图 §4.2 已注明"高可用方案保留为后续演进"。

| 组件 | 单节点风险 | 高可用方案 | 最小节点数 | 资源增量 |
|------|-----------|-----------|-----------|---------|
| **DNS** | 单点故障导致所有服务无法解析 | 部署第二个 dnsmasq 实例，客户端配置多个 DNS | 2 | +1 实例（128 MB）|
| **MySQL** | 宕机导致业务不可用 | 主从复制 + MHA / Orchestrator 自动故障转移 / MGR（组复制） | 主从 2 / MGR 3 | ×2~×3 内存 |
| **Redis** | 缓存失效、会话丢失 | Sentinel 哨兵模式 或 Cluster 模式 | Sentinel 3 / Cluster 6 | ×3~×6 内存 |
| **MongoDB** | 宕机导致文档服务不可用 | Replica Set 副本集（PSS 或 PSA） | 3 | ×3 内存 + arbiter |
| **RabbitMQ** | 消息队列不可用 | Quorum Queue 多节点集群（已是默认推荐队列类型）| 3 | ×3 内存 |
| **Consul** | 服务发现不可用 | 3 节点 Server 集群（Raft 共识） + ACL | 3 | ×3 内存 |
| **K3s** | 业务应用不可用 | 多节点集群 + 嵌入式 etcd HA（K3s 内置）| 3 | ×3 节点资源 |
| **Apollo MySQL（nonprod）** | 配置中心不可用 | 主从 / MGR | 主从 2 | ×2 内存 |
| **Apollo MySQL（prod）** | 生产配置不可用 | 主从（与业务 MySQL 高可用方案一致） | 主从 2 | ×2 内存 |
| **GitLab** | CI/CD 不可用 | GitLab HA 部署（数据库分离 + Redis 集群 + 共享存储） | 5+ | 大幅增加，需独立 PostgreSQL/Redis/NFS |
| **Harbor** | 镜像仓库不可用 | 多节点 + 共享存储（S3/NFS）+ Redis 集群 | 2+ | 中等增加 |
| **edge-nginx (DMZ)** | 公网入口故障 | 双实例 + Keepalived VIP 主备 | 2 × 2（nonprod / prod 各 2） | ×2 实例 |
| **infra-nginx** | 内部入口故障 | 双实例 + Keepalived VIP 主备 | 2 | ×2 实例 |

### 高可用演进顺序建议

```
优先级 1（业务影响最大）:
  ├─ Consul 3 节点集群（生产必须）
  ├─ MySQL 主从（生产推荐）
  └─ K3s 多节点（按业务规模）

优先级 2（数据可用性）:
  ├─ Redis Sentinel
  ├─ MongoDB Replica Set
  └─ RabbitMQ 集群（Quorum Queue 已默认）

优先级 3（基础设施）:
  ├─ DNS 双实例
  ├─ infra-nginx / edge-nginx 双实例 + Keepalived
  └─ Apollo MySQL 主从

优先级 4（研发支撑，可后置）:
  ├─ GitLab HA
  └─ Harbor HA
```

---

## 备份与灾难恢复（可选）

> **默认不配置备份方案**，可在创建部署计划时选择启用。

### 备份策略建议

| 组件 | 备份方式 | 建议频率 | 保留周期 | 恢复时间 |
|------|---------|---------|---------|---------|
| **MySQL（业务 × 5）** | mysqldump 全量 + binlog 增量 | 全量每日 / binlog 实时 | 全量 7 天 / binlog 3 天 | 30 min - 2 h |
| **Apollo MySQL（× 2）** | mysqldump 全量 | 每日 | 7 天 | 30 min |
| **Redis（× 5）** | RDB 快照 + AOF 日志（actions/start.md 已默认开启）| RDB 自动 / AOF 实时 | RDB 24h / AOF 7 天 | 5-30 min |
| **MongoDB（× 5）** | mongodump 或 oplog 增量 | 全量每日 | 7 天 | 30 min - 2 h |
| **Consul（× 5）** | `consul snapshot save` | 每日 | 7 天 | 5-15 min |
| **RabbitMQ（× 5）** | 镜像队列已持久化 + 定义文件 export | 每周（结构变更时）| 30 天 | 30 min |
| **Apollo Portal/Config**（数据在 MySQL）| 同 Apollo MySQL | — | — | — |
| **GitLab** | `gitlab-rake gitlab:backup:create`（内置工具）| 每日 | 7 天 | 1-4 h |
| **Harbor** | 数据库备份（PostgreSQL）+ 镜像存储（NFS/S3 快照）| 每周 | 4 周 | 1-2 h |
| **Nexus** | data 目录全量备份（包括构件 + 配置）| 每周 | 4 周 | 1-2 h |
| **K3s（业务 PVC）** | Velero 或自定义脚本（按 PV 类型）| 按业务定 | 按业务定 | 按业务定 |
| **Prometheus / Loki / Tempo** | 数据保留期内不备份（接受丢失）| — | — | — |

### 跨域备份（生产灾备）

生产域可考虑跨机房 / 跨区域备份：

- **MySQL**：异地从库（延迟复制 6-24h，避免误操作传播）
- **Harbor**：异地镜像同步（Replication 规则）
- **GitLab**：异地远程仓库镜像（`mirroring`）
- **MongoDB**：跨机房 Replica Set（带 hidden / delayed 节点）

---

## 资源监控与告警

部署完成后，通过 Prometheus + Alertmanager 监控资源使用：

| 监控维度 | PromQL 示例 | 告警阈值 |
|---------|------------|---------|
| 容器内存使用率 | `container_memory_usage_bytes / container_spec_memory_limit_bytes` | > 0.8 持续 5 分钟 |
| 容器 CPU 使用率 | `rate(container_cpu_usage_seconds_total[5m])` | > 0.8 持续 5 分钟 |
| 磁盘使用率 | `node_filesystem_avail_bytes / node_filesystem_size_bytes` | < 0.2 |
| MySQL 连接数 | `mysql_global_status_threads_connected / mysql_global_variables_max_connections` | > 0.8 |
| Redis 内存使用率 | `redis_memory_used_bytes / redis_memory_max_bytes` | > 0.85 |
| MongoDB 缓存使用 | `mongodb_wiredtiger_cache_bytes_in_cache / mongodb_wiredtiger_cache_maximum_bytes_configured` | > 0.85 |
| Loki 数据存储增长 | `loki_ingester_chunk_age_seconds` | 按业务定 |
| Tempo 数据存储增长 | `tempo_distributor_received_spans` 速率 | 按业务定 |

> 详细监控规则见 [setup-prometheus/references/conf/prometheus/rules/infra-alerts.yml](../setup-prometheus/references/conf/prometheus/rules/infra-alerts.yml)。

---

## 资源规划速查表

| 想知道 | 看这里 |
|-------|-------|
| 单环境完整部署的最小内存预算 | 本文「单实例资源建议」总计行（约 70 GB）|
| 某个服务的高可用方案 | 本文「高可用演进路径」 |
| 生产数据备份频率 | 本文「备份策略建议」 |
| 多环境部署次数 | [架构蓝图附录 B.1](../architecture-blueprint.md) |
| 各服务 docker-compose 资源 limit | 各 skill `references/docker-compose.yml` |
| 资源监控告警规则 | [setup-prometheus 告警规则](../setup-prometheus/references/conf/prometheus/rules/) |
| 持久化数据卷位置 | 各 skill `references/docker-compose.yml` 的 volumes 段，统一在 `/opt/tech-stack/<service>[-{env}]/data/` |
