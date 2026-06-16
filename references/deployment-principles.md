# 部署原则与规划流程

> **本文档定位**：部署原则、前置准备、实战经验、版本兼容踩坑。
> 五阶段部署任务模板见 [deployment-guide/](deployment-guide/)；架构权威见 [architecture-blueprint.md](../architecture-blueprint.md) 第五部分。

---

## 核心原则

按 architecture-blueprint.md v1.9.0 的多环境隔离架构整理。

1. **DNS 最先部署** — dnsmasq 为所有服务提供 `*.renew.com` 域名解析（极轻量，~5MB 内存），是整个架构基石
2. **infra-nginx 紧随其后** — DNS 部署完成后立即部署，**预配置全部反代规则**（含尚未部署的服务），上游不可达返回 502 不影响 nginx 自身
3. **三大逻辑域物理隔离** — 全局共享层 1 套 + 非生产域 1 套 + 生产域 1 套；非生产 4 环境共用 K3s/LGT/Runner，生产域物理孤岛
4. **环境级中间件完全独立** — MySQL / Redis / MongoDB / RabbitMQ / Consul 各 5 套（dev/sit/fat/uat/prod），无任何数据交集
5. **K3s 仅作业务运行底座** — 业务应用层（前端 / Gateway / Spring Boot 微服务）部署在 K3s；中间件 / LGT 栈 / Apollo / GitLab Runner 全部在 K3s **外部**独立 Docker Compose
6. **Apollo 一次到位合并部署** — nonprod 一个 Compose 拉起 10 容器（MySQL+Portal+4×Config/Admin），prod 一个 Compose 拉起 3 容器（MySQL+Config+Admin），Apollo MySQL 内置且与业务 MySQL 完全分离
7. **可观测性 LGT env 标签隔离** — nonprod 1 套 LGT 通过 `OTEL_RESOURCE_ATTRIBUTES=deployment.environment={env}`（app.sh Pod 级注入）+ Prometheus `relabel_configs` 实现 4 环境逻辑隔离
8. **Metrics 与 Traces/Logs 通路解耦** — Metrics 由 Prometheus 拉取 `/actuator/prometheus`（强制 `OTEL_METRICS_EXPORTER=none`）；Traces/Logs 由 OTel SDK/Agent 推送到 Collector
9. **DNS 直连原则** — 微服务 → 基础设施直接通过 `*.renew.com` 域名连接，不经过任何 Nginx
10. **流量入口分离** — 公网业务流量通过 edge-nginx（DMZ 双实例 nonprod/prod）；内部管理流量通过 infra-nginx（含业务域名内网直达 K3s）
11. **CI/CD 环境最后部署** — GitLab Runner 一站式部署（含 OTel Agent jar），需 K3s + edge-nginx DMZ + Harbor 全部就绪后才能验证 Pipeline
12. **域名替代 IP（铁律二）** — 除 4 类合理例外（DNS hosts.lan / infra-nginx upstream / K3s CoreDNS 转发目标 / kubeconfig API Server）外，所有配置 / 文档 / 脚本禁止硬编码 IP

---

## 部署规划流程

### 第一步：收集服务器信息

| 需收集项 | 示例 | 说明 |
|---------|------|------|
| IP 地址 | 192.168.x.x | 每台服务器的内网 IP |
| SSH 用户名 | root | 登录账号 |
| SSH 密码或密钥 | `~/.ssh/id_rsa` | 认证方式 |
| SSH 端口 | 22 | 默认 22，部分机器可能不同 |
| 域归属 | nonprod / prod / DMZ-nonprod / DMZ-prod / global | 三大逻辑域 + 两条 DMZ 边界 |
| 角色定位（可选）| 中间件 / 计算 / 监控 / 入口 | 用户可指定或由系统建议 |

### 第二步：探测服务器状况

通过 SSH（paramiko）连接每台服务器，自动采集：

```
- 主机名 / 操作系统版本 / 内核版本
- CPU 核数 / 内存总量 / 磁盘容量和使用率
- 系统负载 / 运行时间
- Docker 是否已安装 / 版本
- 内核参数是否已配置（bridge-nf-call-iptables / ip_forward）
- 已占用的端口
- 网络连通性（服务器间互通、外网可达性、镜像源可达性）
```

### 第三步：按域规划部署

按蓝图三大域 + 两条 DMZ 边界规划：

| 域 / 边界 | 部署内容 | 节点要求 |
|-----------|---------|---------|
| **全局共享层** | DNS / infra-nginx / GitLab / Nexus / Harbor | 5 套全局唯一服务，可同机也可分机；建议 GitLab/Nexus 与 infra-nginx 跨机（避免 :2222 / :8082 端口冲突） |
| **非生产域** | K3s nonprod / LGT nonprod / GitLab Runner nonprod / Apollo nonprod（10 容器）/ MySQL/Redis/MongoDB/RabbitMQ/Consul × 4 环境 | 各环境中间件独立机器；K3s + LGT 可同机或分机 |
| **生产域** | K3s prod / LGT prod / Runner prod / Apollo prod（3 容器）/ MySQL/Redis/MongoDB/RabbitMQ/Consul × 1 套 | 物理孤岛，与非生产无任何互通路径 |
| **非生产 DMZ** | edge-nginx (nonprod) | 独立公网 IP / 独立机房 |
| **生产 DMZ** | edge-nginx (prod) | 独立公网 IP / 独立机房 / 物理孤岛 |

### 第四步：用户确认

将部署方案呈现给用户，等待确认。可调整：

- 服务器域归属与角色分配
- 是否跳过某些服务（如暂不部署可观测性层）
- 是否需要高可用配置（默认单节点，演进路径见 [资源规划](resource-planning.md)）
- 是否需要备份方案（默认不配置）
- 密码和配置偏好

### 第五步：生成部署计划

用户确认后，在项目根目录生成 `deployment-plan/` 目录（基于 [deployment-guide/](deployment-guide/) 21 个 task 模板按用户环境填充具体 IP / 节点）。

每个 Task 文件包含：

- 状态标记（⬜ 待执行 / ✅ 完成）
- 目标节点 IP + 域归属
- 对应 Skill 名称 + `--env` 取值
- 前置依赖
- 内存预算
- 执行命令
- 验证标准

### 第六步：按五阶段顺序逐个执行

```
阶段一: 全局基建        → 阶段二: 配置中心     → 阶段三: 非生产建设
                                                     ↓
阶段五: 外网放行        ← 阶段四: 生产防线     ←─────┘
```

每完成一个 Task：

1. 更新 Task 文件状态为 ✅
2. 在 `env/<service>.md` 生成部署报告（含密码、连接方式）
3. 将踩坑回写到对应 skill 的 pitfalls.md
4. 更新 `deployment-plan/README.md` 总览状态

> **整个流程以用户确认为驱动**，每一步都等待用户 review 后再继续。

---

## 前置准备（所有服务器通用）

### 1. Docker 环境安装

```bash
# CentOS 7（官方源已 EOL，使用阿里云 vault 源）
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+' /etc/yum.repos.d/docker-ce.repo
yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin gettext
```

> **CentOS 7 yum 源修复**：CentOS 7 已于 2024-06 EOL，官方 mirrorlist 不可用。需先将 `/etc/yum.repos.d/CentOS-Base.repo` 切换到阿里云 vault 源（`mirrors.aliyun.com/centos-vault/7.9.2009/`），并删除失效的第三方源（如 ius）。

### 2. Docker 镜像加速

国内网络通常无法直接访问 Docker Hub，需配置镜像加速器：

```bash
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "storage-driver": "overlay2",
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me"
  ],
  "insecure-registries": ["harbor.renew.com"]
}
EOF
```

> **若加速器失效**：可尝试显式前缀方式拉取镜像，如 `docker pull docker.1ms.run/library/mysql:8.4`，拉取后 `docker tag` 为原始名称。
>
> **`insecure-registries` 必含 `harbor.renew.com`**：Harbor 默认 HTTP 模式（让出 :80 给 infra-nginx 反代），所有 Docker 客户端必须配置此项才能 push/pull 镜像。

### 3. 内核参数配置（关键）

Docker 网络依赖以下内核参数，**必须在启动 Docker 之前配置**，否则容器网络不通：

```bash
cat >> /etc/sysctl.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
modprobe br_netfilter
sysctl -p
```

| 参数 | 作用 | 缺失后果 |
|------|------|---------|
| `net.bridge.bridge-nf-call-iptables` | 桥接流量经过 iptables 处理 | Docker 容器端口映射失效，外部无法访问容器服务 |
| `net.bridge.bridge-nf-call-ip6tables` | 同上，IPv6 版本 | IPv6 网络不通 |
| `net.ipv4.ip_forward` | 允许 IP 转发 | 容器无法访问外部网络，跨主机通信失败 |

> **实测踩坑**：在 CentOS 7 + Docker 26.1.4 环境下，缺少这些参数会导致容器端口映射看似正常（`ss` 显示监听、`docker ps` 显示端口映射）但实际流量无法到达容器内进程。`tcpdump` 可抓到入站包但进程收不到响应，极难排查。

### 4. 启动 Docker

```bash
systemctl enable docker && systemctl start docker
docker --version && docker compose version
```

### 5. 验证清单

```bash
# 内核参数
sysctl net.bridge.bridge-nf-call-iptables net.ipv4.ip_forward
# 预期输出：
# net.bridge.bridge-nf-call-iptables = 1
# net.ipv4.ip_forward = 1

# Docker
docker run --rm hello-world
# 预期输出：Hello from Docker! ...

# Docker Compose
docker compose version
# 预期输出：Docker Compose version v2.x.x

# DNS 配置（dnsmasq 部署后）
nslookup gitlab.renew.com
# 预期输出：返回 infra-nginx IP（泛解析）

nslookup mysql-fat.renew.com
# 预期输出：返回 hosts.lan 中配置的实际 IP
```

### 6. 配置文件上传规范（AI 工具执行约束）

通过 AI 工具（如 Claude Code）执行远程部署时，上传 `docker-compose.yml` 等含 `${VAR}` 变量引用的文件**必须使用文件复制方式**，禁止使用字符串写入：

| 方式 | 命令 / 方法 | `${VAR}` 是否保留 | 是否允许 |
|------|----------|----------------|---------|
| `scp` 文件复制 | `scp references/docker-compose.yml user@host:/path/` | ✅ 保留 | ✅ 推荐 |
| `sftp.put()` 文件复制 | `sftp.put(local_path, remote_path)` | ✅ 保留 | ✅ 允许 |
| `sftp.open('wb')` + bytes | `f.write(b'...${VAR}...')` | ✅ 保留 | ⚠️ 仅改写时 |
| `sftp.open('w')` + 字符串 | `f.write(f'...${VAR}...')` | ❌ 被吞掉 | ❌ 禁止 |

> **关键原则**：本技术栈大量使用"模板化配置"方案（基于 `envsubst` 或本地 Python 替换）。系统会先上传含 `${VAR}` 占位符的模板文件，再注入环境变量生成最终配置。如果上传过程中 `${VAR}` 被篡改，整个自动化配置链条将断裂。
>
> **特例 — Nginx 服务**：`infra-nginx` / `edge-nginx` 禁止使用 `envsubst` 渲染（会吞掉 `$host` `$remote_addr` 等 nginx 内置变量），必须用 Python 正则替换（仅匹配 `${VAR}` 形式）后再 SFTP 上传。

### 7. Prometheus Exporter 专用用户规范

所有数据服务的 Prometheus Exporter 必须使用**专用监控用户**连接，禁止使用 root/admin 用户。

| 服务 | Exporter 用户 | 权限 | 配置位置 |
|------|------------|------|---------|
| MySQL | `exporter` | `PROCESS, REPLICATION CLIENT, SELECT` | `conf/exporter.my.cnf` + `init/01_create_app_user.sql` |
| Redis | `exporter` | ACL 显式白名单（ping/info/select/dbsize/type/scan/slowlog/latency/config/client/cluster/memory/command/time） | `data/users.acl` |
| MongoDB | `exporter` | `clusterMonitor + read on local` | `init/01_create_app_user.js` |

**原则**：

- Exporter 用户只授予采集指标所需的**最小只读权限**
- 不授予写入、删除、管理等权限
- 密码按统一规则生成（`{Svc}Exp_{16位随机}`），记录在 `.env` 和 `env/<service>.md`
- 用户创建逻辑写入初始化脚本，首次启动自动执行
- **三处密码一致性强制校验**（适用 MySQL / Redis）：`actions/start.md` 在启动前自动校验 `.env` / 配置文件 / init SQL 三处密码，不一致直接退出

### 8. 密码生成规则

部署时所有密码按以下规则即时随机生成：

```
格式：{服务缩写}{角色}_{16位随机大小写字母+数字}
长度：24-28 位
示例：MysRoot_aB3kP7mN9xQ2wE5r
```

| 服务缩写 | 角色缩写 | 说明 |
|---------|---------|------|
| Dns | Adm | DNS Web UI |
| Mys | Root / App / Exp | MySQL 根用户 / 应用 / Exporter |
| Rds | Default / App / Exp | Redis 默认用户 / 应用 / Exporter |
| Mgo | Root / App / Exp | MongoDB 根用户 / 应用 / Exporter |
| Rmq | Adm | RabbitMQ 管理员 |
| Apo | Db | Apollo 内置数据库 |
| Grf | Adm | Grafana 管理员 |
| Hbr | Adm / Db | Harbor 管理员 / 数据库 |

各 skill 的 `.env.example` 顶部已声明对应字段的标签。部署完成后密码记录在 `env/<service>.md` 报告中（**禁止入 git**）。

### 9. 版本兼容性踩坑记录

以下为部署过程中遇到的版本 breaking changes，供后续升级参考：

| 软件 | 版本 | Breaking Change | 影响 | 修复 |
|------|------|----------------|------|------|
| Redis | 8.0 | ACL 文件不允许注释行（`#`） | 启动失败 | `users.acl` 仅保留 ACL 规则，注释/说明写在 README |
| Redis | 8.0 | `aclfile` 优先级高于 `--requirepass` | 密码被覆盖 | 使用 aclfile 统一管理认证；start.md 渲染密码占位符到 `data/users.acl` |
| MongoDB | 8.0 | 移除 `storage.journal.enabled` 配置 | 启动失败 | 删除该配置项 |
| mysqld-exporter | v0.16.0 | 移除 `DATA_SOURCE_NAME` 环境变量 | Exporter 崩溃 | 改用 `.my.cnf` 配置文件（`--config.my-cnf` 命令行参数） |
| dnsmasq | 2.76-2.91 | 与 Docker 网桥共存时静默丢弃查询 | DNS 不响应 | 使用 `bind-dynamic` |
| dnsmasq | — | bridge 模式 UDP 转发超时 | DNS 间歇性失败 | 使用 `network_mode: host` |
| CentOS 7 | 3.10 内核 | 未配 `bridge-nf-call-iptables` 时端口映射静默失败 | 所有容器不通 | 配置内核参数（详见 §3） |
| CentOS 7 | EOL 2024-06 | 官方 yum 源下线 | 无法安装软件 | 切换阿里云 vault 源（详见 §1） |
| Docker Hub | — | 国内直连不可达 | 无法拉取镜像 | 配置镜像加速器（详见 §2） |
| K3s | v1.32+ | 系统镜像从 docker.io 拉取 | Pod ContainerCreating | 配置 `/etc/rancher/k3s/registries.yaml` |
| K3s svclb | — | 自动占用 LoadBalancer 端口 | Traefik Pod Pending | 移除 hostPort，让 svclb 处理；HelmChart 设置 `exposedPort: 8083` |
| K3s CoreDNS | — | 直接修改 `coredns` ConfigMap 会被 Addon Controller 重置 | 转发配置丢失 | 使用 `coredns-custom` ConfigMap 放入 `/var/lib/rancher/k3s/server/manifests/` |
| Traefik | v3.x（K3s 内置） | 默认以非 root 运行 | 无法绑定 1024 以下端口 | 容器内端口改为 8000，宿主机映射 8083 |
| GitLab Runner | 18.x | `--locked` / `--run-untagged` / `--tag-list` 等参数移出 register | 注册失败 | 在 GitLab UI 配置运行策略和 tag |
| Apollo | 2.5.0 | 硬编码映射 `FWS→FAT`，FWS 环境名不可用 | 环境名冲突 | 改用 SIT 作为系统测试环境名 |
| Apollo | 2.5.0 | Portal 配置中 PROD 环境 key 必须用 `PRO` | 生产环境不可达 | Portal 配置 `apollo.portal.envs = dev,sit,fat,uat,pro`；容器后缀仍用 `prod` |
| Harbor | 2.12 | `harbor.yml` 必填 `_version` + `jobservice.job_loggers` + `logger_sweeper_duration` | `prepare` 报 KeyError | 使用 setup-harbor 自带的 `harbor.yml.tpl`（已含全部必填字段） |
| Harbor | 2.12 | 端口变更需重新 `./prepare` | docker compose up 后旧端口仍生效 | 修改 `harbor.yml` 后必须执行 `./prepare && docker compose up -d` |

---

## GitLab Runner 部署说明

GitLab Runner 是 CI/CD 流水线的执行器。本项目 v1.3.0 后 `setup-gitlab-runner` 一站式完成所有准备（Runner 容器 + CI Job 执行环境 + app.sh + kubeconfig + 静态工具 + OTel Java Agent jar + 基础镜像推送）。

### 部署时机

```
阶段三 / 阶段四（按 --env 区分 nonprod / prod）：
    │
    ▼
setup-gitlab-runner start --env <nonprod|prod>
    │
    ├─ 阶段 A：远程环境（Docker / paramiko 连通）
    ├─ 阶段 B：CI Job 环境
    │    ├─ 下载 kubectl-bin / jq-static / docker-static / OTel Agent v2.26.1
    │    ├─ 上传 app.sh / settings.xml
    │    ├─ 配置 kubeconfig（指向对应 K3s 集群）
    │    └─ 推送 Harbor 基础镜像（maven / node / nginx / python）
    ├─ 阶段 C：启动 Runner 容器
    └─ 阶段 D：验证与下一步引导
    │
    ▼
配置 RUNNER_REGISTRATION_TOKEN（从 GitLab UI 获取 glrt- 格式 token）
    │
    ▼
setup-gitlab-runner register --env <nonprod|prod>
    │
    ▼
setup-gitlab-runner verify --env <nonprod|prod>
    │
    ▼
setup-cicd demo（Demo 端到端验证，可选）
```

### 职责划分（v1.3.0）

| Skill | 职责 | Actions |
|-------|------|---------|
| `setup-gitlab-runner` | **CI/CD 执行环境一站式部署** | start / stop / status / verify / logs / register / unregister |
| `setup-cicd` | **业务接入指导** | demo / integrate（不接受 `--env`） |

### OTel Java Agent 管理（v1.7.0）

| 项 | 当前方案 |
|---|---------|
| Agent jar 来源 | setup-gitlab-runner start 阶段 B 自动下载 v2.26.1 |
| 存放位置 | 宿主机 `/opt/tech-stack/cicd/opentelemetry-javaagent.jar` |
| 注入方式 | K8s volumes 挂载到 Pod 容器 `/opt/otel/opentelemetry-javaagent.jar:ro` |
| 跨 JDK 兼容 | JDK 8~21 通用 |
| 更新方式 | 替换宿主机文件即可，无需重建基础镜像 |

### 双方案接入决策（v1.6.0）

| 应用类型 | 接入方案 | OTel 模式 (`ops.otelMode`) |
|---------|---------|--------------------------|
| Spring Boot 3.x（主力）+ JDK 17+ | 方案 A：Micrometer Tracing + OTel Bridge | `bridge` |
| Spring Boot 2.x（兜底）+ JDK 8/11 | 方案 B：OTel Java Agent（字节码注入） | `agent` |
| JDK < 17 | app.sh 自动覆写为 `agent` | — |
| 不接 OTel | `ops.supportOtel=false`，仅保留 Prometheus 拉取 | — |

详见 [setup-cicd/actions/integrate.md](../setup-cicd/actions/integrate.md)。

### 前置条件

| 前置条件 | 检查方式 |
|---------|---------|
| GitLab 已启动 | `curl -I http://gitlab.renew.com/` |
| Harbor 已部署 | `curl -I http://harbor.renew.com/` |
| **K3s 已部署** | `kubectl get nodes` |
| Apollo 已部署（导入 tech.common） | `curl http://apollo-config-fat.renew.com/health` |
| Consul 已部署 | `curl http://consul-fat.renew.com:8500/v1/status/leader` |
| OTel Collector 已部署 | `curl http://otel-nonprod.renew.com:8888/metrics` |
| DNS 配置正确 | `nslookup gitlab.renew.com` 等所有依赖域名 |
| insecure-registries | `cat /etc/docker/daemon.json` 包含 `harbor.renew.com` |

### CI Job 挂载配置

`setup-gitlab-runner start` 一站式完成后，Runner 通过 `--docker-volumes` 显式声明 8 个挂载：

| 挂载路径 | 用途 |
|---------|------|
| `/cache` | GitLab CI 缓存目录 |
| `/var/run/docker.sock` | CI 作业可构建/推送镜像 |
| `/opt/tech-stack/cicd/app.sh` | 部署脚本 |
| `/opt/tech-stack/cicd/settings.xml` | Maven 配置（mirror 到 nexus.renew.com） |
| `/opt/tech-stack/cicd/kubeconfig` | K3s 连接配置 |
| `/opt/tech-stack/cicd/kubectl-bin` | 静态 kubectl（v1.32.0） |
| `/opt/tech-stack/cicd/jq-static` | 静态 jq（1.7.1） |
| `/opt/tech-stack/cicd/opentelemetry-javaagent.jar` | OTel Java Agent v2.26.1（方案 B 兜底） |

> **静态二进制必须**：K3s 安装的 kubectl 是 symlink，CI 容器中无法直接使用；docker CLI 在 alpine 基础镜像可能存在动态链接库依赖问题。三件套（kubectl/jq/docker-static）解决跨基础镜像的可移植问题。

### 验证清单

- [ ] `setup-gitlab-runner start` 已执行（工具、脚本、镜像、Runner 全部就绪）
- [ ] Runner 容器运行中（`docker ps | grep tech-gitlab-runner-{nonprod\|prod}`）
- [ ] GitLab UI 显示 Runner 在线（绿色圆点）
- [ ] Runner tag 配置为 `non-prod` / `prod`
- [ ] CI 镜像中 `kubectl version --client && jq --version && docker --version` 全部通过
- [ ] OTel Agent jar 可挂载到测试 Pod（`ls /opt/otel/opentelemetry-javaagent.jar`）

### 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| CI Job 中 kubectl 找不到 | 未执行 `setup-gitlab-runner start` 或 volumes 未挂载 | 重新 start 或检查 register 时的 `--docker-volumes` |
| Runner 不执行作业 | 未配置 "Run untagged jobs" 或 tag 不匹配 | 在 GitLab UI 配置 Runner tag 与 Pipeline 一致 |
| 镜像拉取失败 | Harbor 未配置 insecure-registries | 配置 daemon.json |
| 注册时连接失败 | DNS 无法解析 gitlab.renew.com | 检查 DNS 配置 |
| CI 中 docker 命令权限不足 | socket 权限 | 生产建议 `usermod -aG docker` 而非 `chmod 666` |
| OTel Agent 挂载失败 | volumes 路径错误或文件不存在 | 检查 `/opt/tech-stack/cicd/opentelemetry-javaagent.jar` 是否存在 |

---

## env/ 目录 — 运行时环境记录与密码本

`env/<service>.md` 是部署完成后生成的"运行时环境记录 + 密码本"。

| 内容 | 示例 |
|------|------|
| 实际 IP / 端口 | `MySQL Dev: 192.168.x.x:3306` |
| 生成的密码 | `MYSQL_ROOT_PASSWORD=MysRoot_aB3kP7mN9xQ2wE5r` |
| 连接命令 | `mysql -h mysql-dev.renew.com -P 3306 -u root -p` |
| Web UI 访问 | `http://consul-dev-ui.renew.com` |
| 部署机器与角色 | `非生产中间件机器，承载 dev/sit MySQL` |

> **`env/` 目录禁止入 git**（已在仓库根 `.gitignore` 中排除）。所有敏感信息只存放在此目录与对应服务的 `.env` 文件中。
