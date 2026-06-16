---
name: setup-gitlab-runner
description: 使用 Docker Compose 部署 GitLab Runner（CI/CD 执行器）及其 CI Job 执行环境（app.sh、kubeconfig、静态工具、基础镜像），一站式完成"git push → Harbor → K3s"所需的全部基础设施。当开发者需要部署 GitLab Runner、准备 CI/CD 执行环境、注册 CI 执行器时触发此 skill。
argument-hint: "[start|stop|status|verify|logs|register|unregister] [--env nonprod|prod] [--host <ip>] [--user <user>] [--password <pass>|--key <path>] [--app-id <id>]"
disable-model-invocation: true
---

> **路径约定**：本文档中 `<skill_dir>` 指 SKILL.md 所在目录（安装后为 `~/.claude/skills/setup-gitlab-runner`）。

# setup-gitlab-runner — GitLab Runner + CI Job 执行环境一站式部署

提供 **Runner 容器 + CI Job 执行环境** 的完整生命周期管理。一条 `/setup-gitlab-runner start` 命令即可完成：静态工具下载、app.sh/settings.xml 上传、kubeconfig 配置、基础镜像推送、Runner 容器启动。

## 文档职责说明

| 文档 | 读者 | 职责 |
|------|------|------|
| **SKILL.md** | Claude Code（AI） | 技能执行指令 — 定义 frontmatter、action 路由、执行流程 |
| **README.md** | 人（开发者/用户） | 入门指引文档 — 安装教程、配置说明、功能介绍、使用示例 |

## 配置

- 配置文件模板位于 `<skill_dir>/references/`
- 远程部署目录：
  - `/opt/tech-stack/gitlab-runner/` — Runner 容器（docker-compose.yml、config、cache）
  - `/opt/tech-stack/cicd/` — CI Job 执行环境（app.sh、kubeconfig、静态工具、settings.xml）

## 用法

```
/setup-gitlab-runner [action] [选项]

action: start（默认）| stop | status | verify | logs | register | unregister

选项:
  --host <ip>        部署目标 IP（默认: localhost）
  --user <user>      SSH 用户名（默认: root，仅远程）
  --password <pass>  SSH 密码（仅远程，与 --key 二选一）
  --key <path>       SSH 私钥路径（仅远程，与 --password 二选一）
  --ssh-port <n>     SSH 端口（默认: 22）
  --env <env>        集群环境（nonprod|prod，默认: nonprod；传入其他值报错退出）
                     nonprod → Runner tag: non-prod，连接非生产 K3s
                     prod    → Runner tag: prod，连接生产 K3s
  --app-id <id>      应用 ID（verify 时检查指定应用部署环境）
```

## Actions

| Action | 说明 |
|--------|------|
| `start` | **一站式部署**：下载静态工具、上传 app.sh/settings.xml、配置 kubeconfig、推送基础镜像、启动 Runner 容器（默认 action） |
| `stop` | 停止 GitLab Runner 容器（保留数据，可用 start 恢复） |
| `status` | 查看 GitLab Runner 容器运行状态 |
| `verify` | 验证 CI/CD 执行环境（Runner 容器 + cicd 目录 + K3s 资源 + Harbor 镜像）；可加 `--app-id` 检查业务应用部署 |
| `logs` | 查看 GitLab Runner 容器日志 |
| `register` | 向 GitLab 注册 Runner（需先启动容器） |
| `unregister` | 从 GitLab 注销 Runner |

## 执行流程

1. 解析参数：提取 ACTION（默认 start）、RUNNER_ENV（默认 nonprod，非 nonprod/prod 报错退出）→ 推导 RUNNER_TAG（nonprod→non-prod，prod→prod）和容器名（tech-gitlab-runner-{env}）、HOST（默认 localhost）、SSH_USER（默认 root）、SSH_PORT（默认 22）、AUTH（password 或 key）
2. 读取 `<skill_dir>/actions/<action>.md` 按步骤执行

## SSH_CMD 约定

action 文件中的 `SSH_CMD "..."` 是伪命令，执行时根据认证方式展开：

```bash
# 密码模式
sshpass -p "${SSH_PASSWORD}" ssh -o StrictHostKeyChecking=no -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} "..."

# 密钥模式
ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} "..."
```

## Executor 类型说明

GitLab Runner 支持多种执行器，本 skill 默认配置 **Docker executor**：

| Executor | 适用场景 | 特点 |
|----------|---------|------|
| **docker** | 推荐，隔离性好 | 每个作业在独立容器中执行，支持指定镜像 |
| **shell** | 简单，直接在宿主机执行 | 无隔离，适合简单脚本 |
| **docker+machine** | 弹性扩展 | 自动创建/销毁云主机 |

**Docker executor 优势**：
- 作业环境隔离，互不影响
- 可指定不同镜像（maven:3.9、node:20 等）
- 支持挂载宿主机 Docker socket 构建镜像

## 重要说明

- **部署前必须配置 `references/.env`**：将所有 `CHANGE_ME_*` 替换为实际值
  - `HARBOR_PASSWORD`：Harbor 镜像仓库密码
  - `NEXUS_PASSWORD`：Nexus 私服密码
  - `RUNNER_REGISTRATION_TOKEN`：GitLab Runner 注册 Token
- `start` action 会自动从 `.env` 读取密码并替换到 `app.sh` 和 `settings.xml`
- 注册 Runner 需要先在 GitLab 获取 registration token（Settings → CI/CD → Runners）
- 挂载 Docker socket 后，CI 作业可构建/推送镜像到 Harbor

---

## 部署顺序（一站式）

> 本 skill 的 `start` 已吸收了原 `setup-cicd start` 的全部产物准备工作，单一命令即可完成 CI/CD 执行环境所有基础设施。

### 部署顺序

```
1. /setup-gitlab-runner start    → 一站式：静态工具 + app.sh + kubeconfig + 基础镜像 + Runner 容器
2. /setup-gitlab-runner register → 注册 Runner 到 GitLab
3. /setup-gitlab-runner verify   → 验证 Runner 容器 + CI Job 执行环境
4. /setup-cicd demo              → （可选）端到端 Demo 验证
```

### 前置条件

| 前置条件 | 说明 | 检查方式 |
|---------|------|---------|
| K3s 已部署 | kubectl 能访问 K3s API | `kubectl get nodes` Ready |
| GitLab 已部署 | Runner 需连接 GitLab | `curl -I http://gitlab.renew.com/` |
| Harbor 已部署 | Runner 镜像与基础镜像存储在 Harbor | `curl -I http://harbor.renew.com/` |
| DNS 已配置 | 能解析 gitlab.renew.com / harbor.renew.com / apollo.renew.com | `nslookup gitlab.renew.com` |
| insecure-registries | Docker 已配置 Harbor | `cat /etc/docker/daemon.json` |

### 完整示例

```bash
# ========== 步骤 1：一站式部署 ==========
/setup-gitlab-runner start --host <RUNNER_HOST> --user root --key ~/.ssh/id_rsa

# ========== 步骤 2：获取 Registration Token（手动） ==========
# GitLab → Settings → CI/CD → Runners → New Project Runner
# 复制生成的 Token（glrt- 开头）

# ========== 步骤 3：配置 Token ==========
ssh root@<RUNNER_HOST> "vi /opt/tech-stack/gitlab-runner/.env"
# 设置: RUNNER_REGISTRATION_TOKEN=glrt-xxxxxxxx

# ========== 步骤 4：注册 Runner ==========
/setup-gitlab-runner register --host <RUNNER_HOST> --user root --key ~/.ssh/id_rsa

# ========== 步骤 5：配置运行策略（GitLab UI） ==========
# Settings → CI/CD → Runners → 编辑 Runner → 启用 "Run untagged jobs"

# ========== 步骤 6：验证 ==========
/setup-gitlab-runner verify --host <RUNNER_HOST> --user root --key ~/.ssh/id_rsa

# ========== 步骤 7：（可选）端到端 Demo ==========
/setup-cicd demo --host <RUNNER_HOST> --user root --key ~/.ssh/id_rsa
```

### 核心组件（/opt/tech-stack/cicd/）

| 组件 | 路径 | 用途 |
|------|------|------|
| `app.sh` | `/opt/tech-stack/cicd/app.sh` | CI Job 部署脚本，自动生成所有 K8s YAML。详见 [app.sh 部署规范](references/app-sh-spec.md) |
| `kubeconfig` | `/opt/tech-stack/cicd/kubeconfig` | K3s 访问凭证（app.sh 通过 KUBECONFIG 变量读取） |
| `kubectl-bin` | `/opt/tech-stack/cicd/kubectl-bin` | 静态 kubectl 二进制（v1.32.0），挂载为容器内 `/usr/local/bin/kubectl` |
| `jq-static` | `/opt/tech-stack/cicd/jq-static` | 静态 jq 二进制（1.7.1），挂载为容器内 `/usr/local/bin/jq` |
| `docker-static` | `/opt/tech-stack/cicd/docker-static` | docker CLI，挂载为容器内 `/usr/local/bin/docker` |
| `settings.xml` | `/opt/tech-stack/cicd/settings.xml` | Maven 配置（Nexus 私服镜像），挂载为容器内 `/root/.m2/settings.xml` |
| `opentelemetry-javaagent.jar` | `/opt/tech-stack/cicd/opentelemetry-javaagent.jar` | OTel Java Agent（v2.26.1），挂载为容器内 `/opt/otel/opentelemetry-javaagent.jar`，用于 Spring Boot 2.x 兜底方案 |

> ⚠️ kubectl 和 jq 必须使用静态二进制存入 cicd 目录。K3s 机器上 `kubectl` 是 k3s symlink；yum 安装的 jq 是动态链接（依赖 libjq.so.1），两者挂载进 Debian/Ubuntu CI 容器均会失败。

### CI Job 挂载配置

注册时会自动配置以下 volumes 挂载：

| 挂载路径 | 用途 |
|---------|------|
| `/cache` | GitLab CI 缓存目录 |
| `/var/run/docker.sock` | CI 作业可构建/推送镜像 |
| `/opt/tech-stack/cicd` | app.sh、kubeconfig、静态工具、settings.xml |
| `cicd/kubectl-bin → /usr/local/bin/kubectl` | 静态 kubectl（start 下载） |
| `cicd/jq-static → /usr/local/bin/jq` | 静态 jq（start 下载） |
| `cicd/docker-static → /usr/local/bin/docker` | docker CLI（start 复制） |
| `cicd/settings.xml → /root/.m2/settings.xml` | Maven 配置 |

---

> **运维记录**：常见问题（Docker socket 权限 / Runner 容器 DNS / 镜像拉取超时 / Runner 18.x 注册参数 / kubectl-jq 静态二进制 / app.sh 双方案分支 / OTel Agent 管理等）见 `references/pitfalls.md`。新发现的问题统一记入 pitfalls.md，actions/ 流程同步修复。
