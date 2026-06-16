# 部署计划 — 2 台服务器方案（开发环境）

## 机器信息

| 角色 | IP | 配置 | 部署内容 |
|------|-----|------|---------|
| Server A（基础设施） | 192.168.82.93 | 8C/15G/99G, CentOS 7 | DNS + 数据 + 中间件 + 服务治理 + 可观测性 + Harbor + K3s + GitLab Runner |
| Server B（研发工具 + DMZ） | 192.168.82.97 | 4C/7.6G/200G, CentOS 7 | GitLab + Nexus + Traefik Ingress |

## SSH 认证

- 账号: root
- 密码: foxconn.88

## 任务列表与执行顺序

部署严格按以下顺序执行，每个任务独立一个文件，完成后标记状态。

### 前置准备（两台机器）

| # | 任务文件 | 目标机器 | 内容 | 状态 |
|---|---------|---------|------|------|
| 00 | `task-00-docker-install-93.md` | 93 | 安装 Docker + Docker Compose | ✅ 完成 |
| 01 | `task-01-docker-install-97.md` | 97 | 安装 Docker + Docker Compose | ✅ 完成 |

### 第零层：DNS（必须最先）

| # | 任务文件 | 目标机器 | Skill | 状态 |
|---|---------|---------|-------|------|
| 02 | `task-02-dns.md` | 93 | setup-dns | ✅ 完成 |

### 第一层：数据 + 中间件 + 服务治理（无互相依赖，可并行但逐个执行）

| # | 任务文件 | 目标机器 | Skill | 状态 |
|---|---------|---------|-------|------|
| 03 | `task-03-mysql.md` | 93 | setup-mysql | ✅ 完成 |
| 04 | `task-04-redis.md` | 93 | setup-redis | ✅ 完成 |
| 05 | `task-05-mongodb.md` | 93 | setup-mongodb | ✅ 完成 |
| 06 | `task-06-rabbitmq.md` | 93 | setup-rabbitmq | ✅ 完成 |
| 07 | `task-07-consul.md` | 93 | setup-consul | ✅ 完成 |
| 08 | `task-08-apollo.md` | 93 | setup-rabbitmq | ✅ 完成 |
| 07 | `task-07-consul.md` | 93 | setup-consul | ✅ 完成 |
| 08 | `task-08-apollo.md` | 93 | setup-apollo | ✅ 完成 |

### 第二层：可观测性后端（无外部依赖）

| # | 任务文件 | 目标机器 | Skill | 状态 |
|---|---------|---------|-------|------|
| 09 | `task-09-tempo.md` | 93 | setup-tempo | ✅ 完成 |
| 10 | `task-10-loki.md` | 93 | setup-loki | ✅ 完成 |

### 第三层：可观测性前端（依赖前两层）

| # | 任务文件 | 目标机器 | Skill | 状态 |
|---|---------|---------|-------|------|
| 11 | `task-11-prometheus.md` | 93 | setup-prometheus | ✅ 完成 |
| 12 | `task-12-grafana.md` | 93 | setup-grafana | ✅ 完成 |
| 13 | `task-13-otel-collector.md` | 93 | setup-otel-collector | ✅ 完成 |

### 研发工具（Server B）

| # | 任务文件 | 目标机器 | Skill | 状态 |
|---|---------|---------|-------|------|
| 14 | `task-14-gitlab.md` | 97 | setup-gitlab | ✅ 完成 |
| 15 | `task-15-nexus.md` | 97 | setup-nexus | ✅ 完成 |

### Harbor（Server A）

| # | 任务文件 | 目标机器 | Skill | 状态 |
|---|---------|---------|-------|------|
| 16 | `task-16-harbor.md` | 93 | setup-harbor | ✅ 完成 |

### 阶段性优化（内部入口 + DNS 重构）

| # | 任务文件 | 目标机器 | 内容 | 状态 |
|---|---------|---------|------|------|
| 17 | `task-17-harbor-port.md` | 93 | Harbor 端口迁移 :80 → :8880 | ✅ 完成 (2026-03-31) |
| 18 | `task-18-infra-nginx.md` | 93 | infra-nginx 部署（内部 Web UI 入口） | ✅ 完成 (2026-04-01) |
| 19 | `task-19-dns-update.md` | 93 | DNS 配置更新（泛解析 + hosts.lan 重构） | ✅ 完成 (2026-03-31) |

### GitLab Runner 注册（K3s 部署前置）

| # | 任务文件 | 目标机器 | Skill | 状态 |
|---|---------|---------|-------|------|
| 20 | `task-20-gitlab-runner.md` | 93 | setup-gitlab-runner | ✅ 完成 (2026-03-26) |

> **说明**：GitLab Runner 是 CI/CD 流水线的执行器，必须在 K3s 部署前完成注册，否则无法执行 CI/CD Pipeline 验证（Task 23）。

### 业务应用层（K3s + Traefik）

| # | 任务文件 | 目标机器 | 内容 | 状态 |
|---|---------|---------|------|------|
| 21 | `task-21-k3s-install.md` | 93 | K3s 安装 + CoreDNS 转发配置 | ✅ 完成 (2026-04-01) |
| 22 | `task-22-traefik.md` | 97 | DMZ Traefik 部署（业务流量入口） | ✅ 完成 (2026-04-01) |

### CI/CD 验证 + 全量验证

| # | 任务文件 | 目标机器 | 内容 | 前置依赖 | 状态 |
|---|---------|---------|------|---------|------|
| 23 | `task-23-cicd-demo.md` | 93 + 97 | CI/CD Pipeline 验证（Demo 项目） | Task 20, 21, 22 | ⬜ 待执行 |
| 24 | `task-24-verify-all.md` | 93 + 97 | 全量验证所有服务 | Task 23 | ⬜ 待执行 |

## 服务依赖与启动顺序

```
第零层（最先部署）:            DNS（dnsmasq）
第一层（内部入口）:            infra-nginx
第二层（无依赖，全部可并行）:  MySQL, Redis, MongoDB, RabbitMQ, Consul, Apollo
第三层（无外部依赖）:          Tempo, Loki
第四层（依赖前两层）:          Prometheus, Grafana, OTel Collector
独立部署（任意时机）:          Nexus, GitLab, Harbor
CI/CD 执行器:                 GitLab Runner（依赖 GitLab，K3s 前部署）
业务应用层:                   K3s
业务入口:                     Traefik Ingress（DMZ 区）
```

## hosts.lan 域名映射（DNS 部署时配置）

```
192.168.82.93   dns.renew.com
192.168.82.93   mysql.renew.com
192.168.82.93   redis.renew.com
192.168.82.93   mongodb.renew.com
192.168.82.93   rabbitmq.renew.com
192.168.82.93   consul.renew.com
# apollo-config-{env}.renew.com 由泛解析 → infra-nginx 代理，无需精确记录
192.168.82.93   otel.renew.com
192.168.82.93   tempo.renew.com
192.168.82.93   loki.renew.com
192.168.82.93   prometheus.renew.com
192.168.82.93   grafana.renew.com
192.168.82.93   harbor.renew.com
192.168.82.93   k3s.renew.com
192.168.82.97   gitlab.renew.com
# nexus.renew.com 通过泛解析 → 93(infra-nginx) 代理，无需精确记录
192.168.82.97   traefik.renew.com
```

## 端口规划

### 93 机器（LAN - 基础设施 + K3s）

| 端口 | 服务 | 状态 |
|------|------|------|
| :53 | dnsmasq | ✅ |
| :80 | infra-nginx | ✅ |
| :2222 | infra-nginx TCP (GitLab SSH) | ✅ |
| :8082 | infra-nginx TCP (Nexus Docker) | ✅ |
| :3306 | MySQL | ✅ |
| :6379 | Redis | ✅ |
| :27017 | MongoDB | ✅ |
| :5672/:15672 | RabbitMQ | ✅ |
| :8500 | Consul | ✅ |
| :8070(Portal)/:8601-8605(Config) | Apollo | ✅ |
| :3000 | Grafana | ✅ |
| :9090 | Prometheus | ✅ |
| :8880 | Harbor | ✅ |
| :6443 | K3s API | ✅ |
| :8083 | K3s Traefik | ✅ |
| — | GitLab Runner（无暴露端口） | ✅ |

### 97 机器（DMZ + 研发工具）

| 端口 | 服务 | 状态 |
|------|------|------|
| :80/:443 | Traefik Ingress | ✅ |
| :8929 | GitLab | ✅ |
| :2222 | GitLab SSH | ✅ |
| :8081 | Nexus HTTP | ✅ |
| :8082 | Nexus Docker | ✅ |

## 内存预算

### 93 机器（15G 可用）

| 服务 | 分配内存 | 累计 |
|------|---------|------|
| OS + 缓冲 | 2G | 2G |
| dnsmasq | 128M | 2.1G |
| MySQL | 2G | 4.1G |
| Redis | 512M | 4.6G |
| MongoDB | 2G | 6.6G |
| RabbitMQ | 512M | 7.1G |
| Consul | 256M | 7.4G |
| Apollo | 512M | 7.9G |
| Tempo | 1.5G | 9.4G |
| Loki | 1G | 10.4G |
| Prometheus+Alertmanager | 1.5G | 11.9G |
| Grafana | 512M | 12.4G |
| OTel Collector | 512M | 12.9G |
| Harbor | 512M | 13.4G |
| infra-nginx | 128M | 13.5G |
| GitLab Runner | 512M | 14G |
| K3s | 1G | 15G |
| **剩余** | **~0G** | |

### 97 机器（7.6G 可用）

| 服务 | 分配内存 | 累计 |
|------|---------|------|
| OS + 缓冲 | 1G | 1G |
| GitLab | 4G | 5G |
| Nexus | 2G | 7G |
| Traefik | 256M | 7.25G |
| **剩余** | **~0.35G** | |

> ⚠️ **97 机器内存风险**：内存紧张，GitLab 已配置 `4g` 限制。构建高负载时可能触发 OOM。
>
> 💡 **GitLab 配置提示**：已采用 `gitlab.rb.template` 持久化方案，SSH 端口为 `2222`。如需手动调整，编辑 `/opt/tech-stack/gitlab/config/gitlab.rb` 并执行 `reconfigure`。

## GitLab Runner 部署说明

GitLab Runner 是 CI/CD 流水线的执行器，负责执行 `.gitlab-ci.yml` 中定义的作业。部署在 93 机器。

### 部署步骤

1. **获取 Registration Token**
   - 登录 GitLab → Settings → CI/CD → Runners
   - 点击 "New Project Runner"
   - 选择 Platform（Linux）、Tags（可选）
   - 复制生成的 Token（glrt- 开头）

2. **部署 Runner**
   ```bash
   /setup-gitlab-runner start --host 192.168.82.93 --user root --password foxconn.88
   ```

3. **配置 Token**
   ```bash
   ssh root@192.168.82.93 "vi /opt/tech-stack/gitlab-runner/.env"
   # 设置 RUNNER_REGISTRATION_TOKEN=glrt-xxxxxxxx
   ```

4. **注册 Runner**
   ```bash
   /setup-gitlab-runner register --host 192.168.82.93 --user root --password foxconn.88
   ```

### 前置条件

- GitLab 已启动并可访问
- 目标机器已配置 DNS 指向 dnsmasq（能解析 `gitlab.renew.com`）
- Docker 已配置 `insecure-registries: ["harbor.renew.com"]`（拉取 Runner 镜像）

### 验证清单

- [ ] GitLab Runner 容器运行中 (`docker ps | grep gitlab-runner`)
- [ ] GitLab 项目设置中显示 Runner 在线
- [ ] Runner 已配置 "Run untagged jobs"（可选，在 GitLab UI 设置）

## 相关文档

| 文档 | 用途 |
|------|------|
| `references/deployment-principles.md` | 部署原则、前置准备、版本踩坑记录 |
| `references/deployment-plan-2servers.md` | 2 台服务器部署方案 |
| `references/deployment-plan-6servers.md` | 6 台服务器部署方案 |
| `setup-gitlab-runner/references/app-sh-spec.md` | 微服务部署规范 |
| `task-*.md` | 各任务详细步骤 |
