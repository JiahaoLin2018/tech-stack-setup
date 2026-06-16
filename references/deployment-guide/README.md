# 部署指南 — 五阶段部署任务索引

> 基于 [architecture-blueprint.md](../../architecture-blueprint.md) v1.9.0 第五部分严格部署顺序产出。

## 本指南是什么

**通用部署模板库**，与服务器数量无关。

- 每个 task 描述一个 skill 实例的部署流程（前置条件、部署命令、验证标准）
- 所有 IP 使用 `<IP>` 占位符，所有密码使用 `<PASS>` 占位符
- 不预设"最小方案 / 标准方案"，不论你有多少台服务器都能使用

## 本指南不是什么

- **不是**可直接执行的部署脚本（没有具体 IP）
- **不是**服务器分配方案（不预设几台机器、怎么分配）
- **不是**运维手册（不含日常运维操作）

## 如何使用本指南

### 步骤一：理解架构

阅读 [architecture-blueprint.md](../../architecture-blueprint.md)，理解：

- 五阶段部署顺序
- 服务依赖关系
- 多环境隔离策略

### 步骤二：确定部署范围

根据实际情况决定：

- 需要部署哪些环境？（仅 Dev？Dev+SIT？全量 Dev/SIT/FAT/UAT/Prod？）
- 哪些 task 是必须的？哪些是可选的？（如 task-35 edge-nginx nonprod 可选）
- 是否跳过某些环境？

### 步骤三：向 AI 提供服务器信息

告知 AI 你的服务器情况，例如：

```
我有 3 台服务器：
  - <GLOBAL_IP>（16C/64G/2T）— 全局区
  - <NONPROD_IP>（16C/64G/2T）— 非生产区
  - <PROD_IP>（8C/32G/1T）— 生产区

我需要部署 Dev + FAT + Prod 三个环境。
```

> 实际告知 AI 时请填入真实 IP，例如 `192.168.1.10`、`10.0.0.10` 等。

### 步骤四：AI 生成执行计划

AI 会基于本模板库，在 `deployment-plan/` 目录下生成具体执行计划：

- 将每个 task 分配到具体服务器
- 确定哪些 task 可并行执行
- 填入具体 IP、域名、端口
- 生成执行顺序与依赖关系

### 步骤五：按计划执行

按生成的执行计划逐步部署，每个 task 完成后执行验证标准确认通过，再进入下一步。

## 两层分离

```
references/deployment-guide/        ← 你正在看的（通用模板库）
  └── 与服务器数量无关
  └── AI 生成执行计划的"素材库"

deployment-plan/                    ← AI 生成的（具体执行计划）
  └── 带具体 IP、密码
  └── 包含并行策略、服务器分配
  └── 你实际执行的"施工图纸"
```

## 部署原则

1. **先全局后局部**：全局基建（DNS / infra-nginx）最先部署
2. **先测试后生产**：非生产环境全部就绪后，才开始生产环境
3. **一个 task 一个 skill**：每个 task 只做一件事，便于聚焦排障
4. **中间件外部部署**：所有中间件 / LGT 栈 / Apollo 在 K3s **外部**独立 Docker Compose
5. **K3s 纯业务底座**：K3s 仅运行业务前端 / Gateway / 微服务

## 五阶段总览

| 阶段 | Task 范围 | 核心内容 | 并行度 |
|------|----------|---------|--------|
| 一：全局基建 | task-01~05 | DNS / infra-nginx / GitLab / Nexus / Harbor | 中（task-03~05 可并行） |
| 二：Apollo 非生产 | task-06 | 配置中心（一次拉起 10 容器） | 单任务 |
| 三：非生产环境 | task-07~35 | 中间件 ×4 环境 + K3s + LGT + Runner + 验证 | 高（多环境并行） |
| 四：生产环境 | task-36~48 | 生产基础设施（物理隔离）+ Apollo prod | 中 |
| 五：外网入口 | task-49~50 | edge-nginx prod + 上线验证 | 低 |

> **总计 50 个 task**（task-50 为上线验证流程，无对应 skill 调用）。

## 任务依赖 DAG

```
阶段一（全局基建）
  task-01 (DNS)
       │
       ├─→ task-02 (infra-nginx)
       │
       ├─→ task-03 (GitLab) ────┐
       ├─→ task-04 (Nexus) ─────┼─→ 阶段三依赖
       └─→ task-05 (Harbor) ────┘

阶段二（Apollo nonprod，10 容器合并部署）
  task-06 (Apollo nonprod) ←─ task-01

阶段三（非生产环境）
  ┌─────────────────────────────────────────────────────────┐
  │ 并行组 A：Dev 环境中间件（task-07~11）                   │
  │ 并行组 B：SIT 环境中间件（task-12~16）                   │
  │ 并行组 C：FAT 环境中间件（task-17~21）                   │
  │ 并行组 D：UAT 环境中间件（task-22~26）                   │
  │   每组 5 个 task 互无依赖，可全部并行                    │
  └─────────────────────────────────────────────────────────┘
  ┌─────────────────────────────────────────────────────────┐
  │ 并行组 E：计算底座 + 可观测性（task-27~32）              │
  │   task-27 (k3s-nonprod)                                 │
  │   task-28 (tempo-nonprod) ┐                             │
  │   task-29 (loki-nonprod)  ├─ 无依赖，可并行              │
  │   task-30 (prometheus-nonprod) ← 依赖 28/29              │
  │   task-31 (grafana-nonprod)    ← 依赖 30                 │
  │   task-32 (otel-collector-nonprod) ← 依赖 28/29          │
  └─────────────────────────────────────────────────────────┘
       │
       ├─→ task-33 (runner-nonprod) ← 03 + 05 + 27
       ├─→ task-34 (cicd-demo) ← 06 + 33
       └─→ task-35 (edge-nginx-nonprod) ← 27 [可选]

阶段四（生产环境）
  ┌─────────────────────────────────────────────────────────┐
  │ 并行组 F：生产中间件（task-36~40）全部可并行              │
  └─────────────────────────────────────────────────────────┘
  ┌─────────────────────────────────────────────────────────┐
  │ 并行组 G：生产计算底座（task-41~46）                     │
  │   task-41 (k3s-prod)                                    │
  │   task-42 (tempo-prod) ┐                                │
  │   task-43 (loki-prod)  ├─ 无依赖，可并行                 │
  │   task-44 (prometheus-prod) ← 依赖 42/43                │
  │   task-45 (grafana-prod)    ← 依赖 44                   │
  │   task-46 (otel-collector-prod) ← 依赖 42/43            │
  └─────────────────────────────────────────────────────────┘
       │
       ├─→ task-47 (apollo-prod) ← task-06（Portal 跨网段挂载）
       └─→ task-48 (runner-prod) ← 03 + 05 + 41

阶段五（外网入口）
  task-49 (edge-nginx-prod) ← task-41
       │
       └─→ task-50 (上线验证) ← 全部前置任务
```

## 任务索引（50 项）

| # | 阶段 | 任务 | Skill | 前置 | 核心产出 |
|---|------|------|-------|------|---------|
| 01 | 一 | DNS | `setup-dns` | — | hosts.lan 域名映射，37 条直连域名 |
| 02 | 一 | infra-nginx | `setup-infra-nginx` | 01 | 全部反代规则预配置（含尚未部署的服务） |
| 03 | 一 | GitLab | `setup-gitlab` | 01 | 代码托管平台 |
| 04 | 一 | Nexus | `setup-nexus` | 01 | Maven / NPM 私服 |
| 05 | 一 | Harbor | `setup-harbor` | 01 | Docker 镜像仓库 |
| 06 | 二 | Apollo nonprod | `setup-apollo --env nonprod` | 01, 02 | Portal + Config/Admin ×4 + 内置 MySQL（10 容器） |
| 07 | 三 | MySQL Dev | `setup-mysql --env dev` | 01 | mysql-dev.renew.com:3306 |
| 08 | 三 | Redis Dev | `setup-redis --env dev` | 01 | redis-dev.renew.com:6379 |
| 09 | 三 | MongoDB Dev | `setup-mongodb --env dev` | 01 | mongodb-dev.renew.com:27017 |
| 10 | 三 | RabbitMQ Dev | `setup-rabbitmq --env dev` | 01 | rabbitmq-dev.renew.com:5672 |
| 11 | 三 | Consul Dev | `setup-consul --env dev` | 01 | consul-dev.renew.com:8500 |
| 12 | 三 | MySQL SIT | `setup-mysql --env sit` | 01 | mysql-sit.renew.com:3306 |
| 13 | 三 | Redis SIT | `setup-redis --env sit` | 01 | redis-sit.renew.com:6379 |
| 14 | 三 | MongoDB SIT | `setup-mongodb --env sit` | 01 | mongodb-sit.renew.com:27017 |
| 15 | 三 | RabbitMQ SIT | `setup-rabbitmq --env sit` | 01 | rabbitmq-sit.renew.com:5672 |
| 16 | 三 | Consul SIT | `setup-consul --env sit` | 01 | consul-sit.renew.com:8500 |
| 17 | 三 | MySQL FAT | `setup-mysql --env fat` | 01 | mysql-fat.renew.com:3306 |
| 18 | 三 | Redis FAT | `setup-redis --env fat` | 01 | redis-fat.renew.com:6379 |
| 19 | 三 | MongoDB FAT | `setup-mongodb --env fat` | 01 | mongodb-fat.renew.com:27017 |
| 20 | 三 | RabbitMQ FAT | `setup-rabbitmq --env fat` | 01 | rabbitmq-fat.renew.com:5672 |
| 21 | 三 | Consul FAT | `setup-consul --env fat` | 01 | consul-fat.renew.com:8500 |
| 22 | 三 | MySQL UAT | `setup-mysql --env uat` | 01 | mysql-uat.renew.com:3306 |
| 23 | 三 | Redis UAT | `setup-redis --env uat` | 01 | redis-uat.renew.com:6379 |
| 24 | 三 | MongoDB UAT | `setup-mongodb --env uat` | 01 | mongodb-uat.renew.com:27017 |
| 25 | 三 | RabbitMQ UAT | `setup-rabbitmq --env uat` | 01 | rabbitmq-uat.renew.com:5672 |
| 26 | 三 | Consul UAT | `setup-consul --env uat` | 01 | consul-uat.renew.com:8500 |
| 27 | 三 | K3s nonprod | `setup-k3s --env nonprod` | 01 | 业务应用底座，4 Namespace（dev/sit/fat/uat） |
| 28 | 三 | Tempo nonprod | `setup-tempo --env nonprod` | 01 | 链路追踪后端 |
| 29 | 三 | Loki nonprod | `setup-loki --env nonprod` | 01 | 日志聚合后端 |
| 30 | 三 | Prometheus nonprod | `setup-prometheus --env nonprod` | 28, 29, 11/16/21/26 | 指标采集 + Alertmanager |
| 31 | 三 | Grafana nonprod | `setup-grafana --env nonprod` | 30 | 统一可视化看板 |
| 32 | 三 | OTel Collector nonprod | `setup-otel-collector --env nonprod` | 28, 29 | 遥测数据网关 |
| 33 | 三 | Runner nonprod | `setup-gitlab-runner --env nonprod` | 03, 05, 27, 32 | CI 环境 + OTel Agent + app.sh |
| 34 | 三 | CI/CD Demo | `setup-cicd demo` | 06, 33 | 端到端 Pipeline 验证 |
| 35 | 三 | edge-nginx nonprod | `setup-edge-nginx --env nonprod` | 27 | 非生产公网入口（可选）|
| 36 | 四 | MySQL Prod | `setup-mysql --env prod` | 01 | mysql-prod.renew.com:3306 |
| 37 | 四 | Redis Prod | `setup-redis --env prod` | 01 | redis-prod.renew.com:6379 |
| 38 | 四 | MongoDB Prod | `setup-mongodb --env prod` | 01 | mongodb-prod.renew.com:27017 |
| 39 | 四 | RabbitMQ Prod | `setup-rabbitmq --env prod` | 01 | rabbitmq-prod.renew.com:5672 |
| 40 | 四 | Consul Prod | `setup-consul --env prod` | 01 | consul-prod.renew.com:8500（强制 ACL + Gossip）|
| 41 | 四 | K3s prod | `setup-k3s --env prod` | 01 | 生产业务底座（物理孤岛）|
| 42 | 四 | Tempo prod | `setup-tempo --env prod` | 01 | 生产链路追踪 |
| 43 | 四 | Loki prod | `setup-loki --env prod` | 01 | 生产日志聚合 |
| 44 | 四 | Prometheus prod | `setup-prometheus --env prod` | 42, 43, 40 | 生产指标采集 |
| 45 | 四 | Grafana prod | `setup-grafana --env prod` | 44 | 生产监控看板 |
| 46 | 四 | OTel Collector prod | `setup-otel-collector --env prod` | 42, 43 | 生产遥测网关 |
| 47 | 四 | Apollo prod | `setup-apollo --env prod` | 06 | 生产 Config/Admin + 独立 MySQL（3 容器） |
| 48 | 四 | Runner prod | `setup-gitlab-runner --env prod` | 03, 05, 41 | 生产 CI 环境 |
| 49 | 五 | edge-nginx prod | `setup-edge-nginx --env prod` | 41 | 生产公网入口（独立公网 IP）|
| 50 | 五 | 上线验证 | — | 全部 | 端到端验证清单 |

## 并行执行说明

当用户有多台服务器时，AI 可基于本指南生成并行执行计划。

### 典型并行场景

| 场景 | 可并行执行的 task | 收益 |
|------|------------------|------|
| 阶段一研发资产 | task-03/04/05 同时部署在不同机器 | 缩短 2/3 时间 |
| 阶段三同环境中间件 | 每环境 task-07~11（Dev）/ 12~16（SIT）等 5 个 task 互无依赖 | 单环境 5 倍并行 |
| 阶段三跨环境 | task-07~26（20 个）分布到多机器 | 大幅缩短部署周期 |
| 阶段四生产基础设施 | task-36~46（11 个）大部分可并行 | 生产环境快速就绪 |

### LGT 栈串行依赖

`Tempo / Loki` → `Prometheus` → `Grafana` + `OTel Collector` 须按依赖顺序执行（同一域内）。

## 部署结果存放说明

每个 task 执行后会产生三类产物，分别有不同的存放约定：

### ① 凭证 / 配置报告 — `env/{service}[-{env}].md`

| 内容 | 说明 |
|------|------|
| 真实 IP / 端口 / 域名 | 该服务实际部署的网络信息 |
| 账号 / 密码 / Token | 按 `{服务缩写}{角色}_{16位随机}` 规则生成（如 `MysRoot_aB3kP7mN9xQ2wE5r`），由 skill 在 `actions/start.md` 执行时随机产出并写入 |
| 版本 / 部署时间 | 该实例的部署日期和镜像版本 |
| 变更日志 | 后续运维操作记录 |

**命名规则**：

- 全局唯一服务（task-01~05）：`env/dns.md` / `env/gitlab.md` / `env/nexus.md` / `env/harbor.md` / `env/infra-nginx.md`
- 多环境服务（task-07~26、36~40）：`env/mysql-dev.md` / `env/redis-prod.md` 等
- 域级共用服务（task-27~33、41~48）：`env/k3s-nonprod.md` / `env/grafana-prod.md` 等

**git 存档约定**：

- `env/*.md` 包含敏感信息，**已在 `.gitignore` 中排除**（保留 `env/README.md` 作为索引模板）
- 已被 git 跟踪的旧报告需手动 `git rm --cached env/<file>.md` 才能真正脱钩
- 生产凭证建议用密钥管理系统（HashiCorp Vault / AWS Secrets Manager）替代纯文本报告

### ② 命令实时输出 — 当前 AI 会话

`/setup-* start` 等命令的 stdout / stderr / 容器健康检查结果由执行该命令的 AI 会话（Claude Code 或运维终端）实时呈现。

- **不持久化**：会话关闭后输出消失
- **如需归档**：用户自行复制关键日志到 `deployment-plan/` 或运维记录系统
- **失败排障**：执行 `/setup-* logs` 查看容器日志，或参考各 skill 的 `actions/logs.md`

### ③ 跨任务进度追踪 — `deployment-plan/`

`deployment-guide/` 是静态模板库（与服务器数量无关）；用户实际执行 50 个 task 的进度追踪应放在动态生成的 `deployment-plan/` 中：

```
deployment-plan/
├── README.md              ← AI 基于服务器信息生成的执行总览
├── progress.md            ← task 完成状态打勾表
├── server-allocation.md   ← task → 服务器映射 + 并行策略
└── ...                    ← 其他用户自定义的执行记录
```

> `deployment-plan/` 由 AI 在用户提供服务器信息后动态生成，不在本指南范围内。

### 三类产物速查

| 产物 | 存放 | 谁写 | 是否入 git |
|------|------|------|-----------|
| 凭证报告 | `env/{service}[-{env}].md` | skill 自动写 + 用户补充 | ❌ 已 .gitignore |
| 命令输出 | AI 会话窗口 | skill 执行时实时输出 | — 不落盘 |
| 进度追踪 | `deployment-plan/` | AI 生成 + 用户维护 | 视用户决定 |

## 占位符约定

各 task 文件统一使用以下占位符：

| 占位符 | 含义 |
|--------|------|
| `<IP>` | 单一 IP 地址，由用户在实际部署时替换 |
| `<HOST>` | 主机域名或 IP（部署机器） |
| `<USER>` | SSH 登录用户名 |
| `<PASS>` | SSH 登录密码 |
| `<DNS_IP>` / `<NGINX_IP>` / 等 | 特定服务 IP（部署 task 中会注明） |

## 文档导航

| 主题 | 路径 |
|------|------|
| 架构蓝图（最终权威）| [architecture-blueprint.md](../../architecture-blueprint.md) |
| 网络架构 | [references/network-architecture.md](../network-architecture.md) |
| 部署原则 | [references/deployment-principles.md](../deployment-principles.md) |
| 资源规划 | [references/resource-planning.md](../resource-planning.md) |
| 配置参考 | [references/configuration-reference.md](../configuration-reference.md) |
| 可观测性数据流 | [references/observability-pipeline.md](../observability-pipeline.md) |
