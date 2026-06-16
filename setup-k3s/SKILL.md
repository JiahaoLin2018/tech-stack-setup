---
name: setup-k3s
description: K3s 轻量级 Kubernetes 集群的完整生命周期管理，支持非生产（dev/sit/fat/uat）和生产（prod）双集群模式，含 CoreDNS 转发配置。当开发者需要部署、卸载、查看状态、验证 K3s 集群时触发此 skill。
argument-hint: "[start|stop|status|verify|logs] [--env nonprod|prod] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]"
disable-model-invocation: true
---

> **路径约定**：本文档中 `<skill_dir>` 指 SKILL.md 所在目录（安装后为 `~/.claude/skills/setup-k3s`）。

# setup-k3s — K3s 双集群（nonprod / prod）

提供 K3s 轻量级 Kubernetes 集群的完整生命周期管理，支持非生产和生产双集群模式，支持远程服务器 SSH 部署。

- **非生产集群**（`--env nonprod`）：Namespace dev / sit / fat / uat，共用一套 K3s
- **生产集群**（`--env prod`）：独立物理机 / 隔离 VPC，仅运行生产微服务

## 文档职责说明

| 文档 | 读者 | 职责 |
|------|------|------|
| **SKILL.md** | Claude Code（AI） | 技能执行指令 — 定义 frontmatter、action 路由、执行流程 |
| **README.md** | 人（开发者/用户） | 入门指引文档 — 安装教程、配置说明、功能介绍、使用示例 |
| **pitfalls.md** | 所有人 | 踩坑记录与运维经验 |

## 前置依赖

| 依赖 | 说明 |
|------|------|
| setup-dns | DNS 服务已部署，域名解析正常 |
| DNS 配置完成 | hosts.lan 中已配置 K3s 节点域名 |

## 安装方式说明

K3s 与本项目其他服务的部署方式不同：

| 对比项 | 基础设施服务（MySQL/Redis 等） | K3s |
|--------|------------------------------|-----|
| 部署方式 | Docker Compose 容器 | 二进制 + systemd 系统服务 |
| 管理目录 | `/opt/tech-stack/<service>/` | 不适用 |
| 数据目录 | `/opt/tech-stack/<service>/data/` | `/var/lib/rancher/k3s/` |
| 配置目录 | `/opt/tech-stack/<service>/conf/` | `/etc/rancher/k3s/` |
| 服务管理 | `docker compose up/down` | `systemctl start/stop k3s` |
| 依赖运行时 | Docker | 内置 containerd（不依赖 Docker） |

> **为什么不放在 `/opt/tech-stack/`**：K3s 是二进制直接安装的系统服务，自带 containerd 运行时，官方推荐此方式。改用 Docker 部署会增加额外开销且缺少官方支持。

## 配置

- 配置文件模板位于 `<skill_dir>/references/`
- K3s 二进制路径：`/usr/local/bin/k3s`
- K3s 数据目录：`/var/lib/rancher/k3s/`
- K3s 配置目录：`/etc/rancher/k3s/`
- kubeconfig：`/etc/rancher/k3s/k3s.yaml`
- 镜像加速：`/etc/rancher/k3s/registries.yaml`
- Token 备份：`/root/.k3s_token`

## 用法

```
/setup-k3s [action] [选项]

action: start（默认）| stop | status | verify | logs

选项:
  --env <env>        集群环境（nonprod|prod，默认: nonprod；传入其他值报错退出）
  --host <ip>        部署目标 IP（默认: localhost）
  --user <user>      SSH 用户名（默认: root，仅远程）
  --password <pass>  SSH 密码（仅远程，与 --key 二选一）
  --key <path>       SSH 私钥路径（仅远程，与 --password 二选一）
  --ssh-port <n>     SSH 端口（默认: 22）
  --token <token>    K3s 集群 token（默认: 自动生成）
```

## Actions

| Action | 说明 |
|--------|------|
| `start` | 安装 K3s 集群（默认 action），按 `--env` 创建对应 Namespace |
| `stop` | 卸载 K3s 集群 |
| `status` | 查看 K3s 集群运行状态 |
| `verify` | 验证 K3s 集群和 CoreDNS 转发 |
| `logs` | 查看 K3s 服务日志 |

## 执行流程

1. 解析参数：提取 ACTION（默认 start）、K3S_ENV（默认 nonprod，非 nonprod/prod 报错退出）、HOST（默认 localhost）、SSH_USER（默认 root）、SSH_PORT（默认 22）、AUTH（password 或 key）、K3S_TOKEN
2. 读取 `<skill_dir>/actions/<action>.md` 按步骤执行

## SSH_CMD 约定

action 文件中的 `SSH_CMD "..."` 是伪命令，执行时根据认证方式展开：

```bash
# 密码模式
sshpass -p "${SSH_PASSWORD}" ssh -o StrictHostKeyChecking=no -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} "..."

# 密钥模式
ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} "..."
```

## 资源预算

| 组件 | 内存 |
|------|------|
| K3s Server | ~512MB |
| CoreDNS | ~50MB |
| Traefik | ~100MB |
| **合计** | **~650MB** |

## 架构说明

```
┌─────────────────────────────────────────┐
│  K3s 集群（业务应用层）                  │
│  前端 | Gateway | Spring Boot 微服务     │
└─────────────────────────────────────────┘
                    │
                    │ *.renew.com 域名连接
                    ▼
┌─────────────────────────────────────────┐
│  Docker Compose（基础设施层）            │
│  MySQL | Redis | Consul | Apollo | ...  │
└─────────────────────────────────────────┘
```

K3s 仅管理业务应用，基础设施保持 Docker Compose 部署。

## 业务 Pod 接入边界

setup-k3s 只提供**纯粹的业务运行底座**，不参与遥测打标和服务注册：

| 关注点 | 由谁处理 |
|------|---------|
| Pod 启动时注入 `OTEL_RESOURCE_ATTRIBUTES=deployment.environment={env},service.namespace={env}` | setup-gitlab-runner 的 `app.sh` |
| Pod 注入 `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-{nonprod\|prod}.renew.com:4317` | 同上 |
| Pod 通过 Consul 注册 `metrics` tag（供 Prometheus consul_sd 发现） | 业务 Spring Boot `application.yml` |
| Pod 拉取 Apollo 配置（`apollo.meta=http://apollo-config-{env}.renew.com`） | `app.sh` 注入环境变量 |
| Pod 通过 DNS 域名直连基础设施（mysql-{env}.renew.com 等） | CoreDNS 转发 `.renew.com` 到 dnsmasq（本 skill 配置） |

> 详见 `setup-cicd/actions/integrate.md`（业务接入指南）和 `setup-gitlab-runner/references/app.sh`（运行时注入逻辑）。

## 注意事项

### 镜像拉取

国内网络无法直接访问 Docker Hub，安装 K3s 后**必须立即配置镜像加速器**：
- 配置文件：`/etc/rancher/k3s/registries.yaml`
- 模板位置：`<skill_dir>/references/registries.yaml`
- 配置后需重启 K3s：`systemctl restart k3s`

**关键配置项**：
```yaml
mirrors:
  # Docker Hub 镜像加速
  docker.io:
    endpoint:
      - "https://docker.1ms.run"
  # Harbor 私有仓库（通过 infra-nginx 代理，HTTP :80）
  # K3s 默认尝试 HTTPS 443，需显式指定 HTTP 地址
  harbor.renew.com:
    endpoint:
      - "http://harbor.renew.com"
```

> **踩坑**：Harbor 通过 infra-nginx 代理在 HTTP :80 提供服务，K3s 默认尝试 HTTPS 443 端口连接，会导致 `dial tcp :443: connection refused`。必须在 registries.yaml 中显式配置 Harbor 的 HTTP 地址（无端口，走 infra-nginx）。

### Traefik 端口

| 部署模式 | Traefik 端口 | 说明 |
|---------|-------------|------|
| 标准部署（6台服务器） | 8080 | 默认端口 |
| 单机部署 | **8083** | :80 被 infra-nginx 占用（Apollo 已迁移至 8601+，8080 空闲） |

端口在 `references/deployment-plan-2servers.md` 或 `references/deployment-plan-6servers.md` 中预先规划，部署时无需试错。

### CoreDNS 转发

CoreDNS 配置将 `.renew.com` 域名转发到 dnsmasq，Pod 才能访问基础设施。

> **踩坑**：
> - K3s 使用 **Addon Controller** 管理 CoreDNS ConfigMap
> - 直接修改 `coredns` ConfigMap 会被 K3s 重置（重启时触发）
> - 正确方式：创建 `coredns-custom` ConfigMap，通过 `import /etc/coredns/custom/*.override` 加载

**配置文件**：`<skill_dir>/references/coredns-custom.yaml`

## 故障排查

| 症状 | 可能原因 | 解决方案 |
|------|---------|---------|
| Pod ContainerCreating | 镜像拉取失败 | 检查 registries.yaml |
| ImagePullBackOff harbor.renew.com | Harbor 配置缺失 | 添加 harbor.renew.com mirror |
| Traefik bind: permission denied | 容器内端口 < 1024 | 容器内端口改为 8000 |
| Traefik Pending | hostPort 冲突 | 移除 hostPort，用 svclb |
| Pod 无法解析 *.renew.com | CoreDNS 转发丢失 | 检查 coredns-custom ConfigMap |

详细排查步骤见 `actions/start.md` 步骤 7~9。

## 踩坑记录规则

> 部署过程中遇到的问题，按以下流程处理：
> 1. **修复模板**：将 fix 写入 `references/` 配置文件或 `actions/start.md` 流程步骤，确保下次部署自动生效
> 2. **记录 pitfalls.md**：追加踩坑条目，注明问题现象、根因和修复方案
> 3. **更新端口规划**：若涉及端口调整，同步更新 `references/deployment-plan-*.md`
