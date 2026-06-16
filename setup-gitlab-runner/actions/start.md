# action: start — 一站式启动 CI/CD 执行环境

> **本 action 完成"让 CI 能跑"的所有基础设施准备**：下载静态工具、上传 app.sh/settings.xml、配置 kubeconfig、创建 Harbor Secret、推送基础镜像、启动 Runner 容器。执行完成后 `/opt/tech-stack/cicd/` 完整就绪，Runner 容器挂载直接可用。
>
> **前提**：K3s 已部署（`kubectl get nodes` Ready）、Harbor 已部署、DNS 指向 dnsmasq。

## 步骤

> **文件上传约束**：上传 docker-compose.yml、app.sh、settings.xml 等含 `${VAR}` 变量引用的文件时，必须使用文件复制方式（`scp` 或 `sftp.put()`），禁止使用 Python 字符串写入（会导致 `${VAR}` 被吞掉变为空值）。详见 `references/deployment-principles.md` 前置准备第 6 节。

---

## 步骤 0：解析 --env 参数（B 类契约）

```
RUNNER_ENV = --env 参数值，默认 nonprod
若 RUNNER_ENV 不是 nonprod 或 prod：
  输出错误："[ERROR] --env 参数无效：'${RUNNER_ENV}'。允许值：nonprod | prod"
  退出执行

根据 RUNNER_ENV 推导：
  若 RUNNER_ENV = nonprod → RUNNER_TAG = non-prod
  若 RUNNER_ENV = prod    → RUNNER_TAG = prod
  RUNNER_CONTAINER_NAME = tech-gitlab-runner-${RUNNER_ENV}
```

| --env | Runner tag | 容器名 | 连接 K3s |
|-------|-----------|--------|---------|
| nonprod（默认） | `non-prod` | `tech-gitlab-runner-nonprod` | 非生产集群 |
| prod | `prod` | `tech-gitlab-runner-prod` | 生产集群 |

---

## 阶段 A：远程环境准备

### 步骤 1：检查本地 SSH 工具

```bash
# 密码模式
which sshpass > /dev/null 2>&1 || echo "MISSING_SSHPASS"
# 密钥模式
ls ${SSH_KEY_PATH} 2>/dev/null || echo "MISSING_KEY"
```

- 缺少 sshpass（密码模式）→ 提示 `apt install sshpass` 或改用 `--key`
- 密钥文件不存在 → 提示检查路径

### 步骤 2：测试 SSH 连接

```bash
# 密码模式
sshpass -p "${SSH_PASSWORD}" ssh -o StrictHostKeyChecking=no -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} "echo OK"
# 密钥模式
ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} "echo OK"
```

- 连接失败 → 报告错误信息，终止执行

### 步骤 3：检查远程 Docker（未安装则自动安装）

```bash
SSH_CMD "docker info > /dev/null 2>&1 || (curl -fsSL https://get.docker.com | sh && systemctl enable --now docker)"
```

### 步骤 4：创建部署目录

```bash
SSH_CMD "mkdir -p /opt/tech-stack/cicd /opt/tech-stack/gitlab-runner"
```

> ⚠️ 若 `kubeconfig` 被错误创建为目录（K3s 部署前 cicd 目录已存在时偶发），先清理：

```bash
SSH_CMD "[ -d /opt/tech-stack/cicd/kubeconfig ] && rm -rf /opt/tech-stack/cicd/kubeconfig && echo 'CLEANED stale kubeconfig dir' || true"
```

---

## 阶段 B：CI Job 执行环境准备（/opt/tech-stack/cicd/）

> 本阶段产物为 Runner 容器挂载依赖，必须在 Runner 启动前完成。

### 步骤 5：下载静态工具到 cicd 目录（kubectl-bin、jq-static、docker-static）

> **目的**：以静态二进制存入 `/opt/tech-stack/cicd/`，通过 config.toml volumes 挂载到 CI Job 容器，实现一次部署、所有 Pipeline 共享。
>
> ⚠️ **不要用系统包管理器安装，也不要挂载 `/usr/local/bin/kubectl` 或 `/usr/bin/jq`**：
> - 在 K3s 机器上，`kubectl` 是 k3s 的**符号链接**，mount 到 CI 容器后执行的是 k3s 二进制，行为异常
> - yum/apt 安装的 jq 是**动态链接**的（依赖 `libjq.so.1`），挂载到 Ubuntu/Debian CI 容器后找不到对应 so 文件
> - 静态二进制是唯一可靠方案：不依赖宿主机 libc，任何 Linux 容器都能执行

#### 5.1 下载静态 kubectl

```bash
SSH_CMD "[ -f /opt/tech-stack/cicd/kubectl-bin ] && /opt/tech-stack/cicd/kubectl-bin version --client 2>/dev/null && echo 'KUBECTL_EXISTS' || echo 'KUBECTL_MISSING'"
```

- 返回 `KUBECTL_EXISTS` → 跳过
- 返回 `KUBECTL_MISSING` → 下载（先尝试宿主机直连，失败则借助 Docker 容器）：

```bash
# 方案1：宿主机直连 CN 镜像
SSH_CMD "curl -sfL --connect-timeout 10 \
  https://kubernetes.pek3b.qingstor.com/kubectl/v1.32.0/bin/linux/amd64/kubectl \
  -o /opt/tech-stack/cicd/kubectl-bin && \
  chmod +x /opt/tech-stack/cicd/kubectl-bin && echo DOWNLOAD_OK || echo DOWNLOAD_FAIL"
```

若宿主机无法访问外网（返回 DOWNLOAD_FAIL）：

```bash
# 方案2：借助 Maven 容器下载（容器网络通常可访问外网）
SSH_CMD "docker run --rm \
  -v /opt/tech-stack/cicd:/opt/tech-stack/cicd \
  maven:3.9-eclipse-temurin-21 bash -c \
  \"curl -sfL --connect-timeout 15 \
    https://kubernetes.pek3b.qingstor.com/kubectl/v1.32.0/bin/linux/amd64/kubectl \
    -o /opt/tech-stack/cicd/kubectl-bin && \
    chmod +x /opt/tech-stack/cicd/kubectl-bin && echo DOWNLOAD_OK || echo DOWNLOAD_FAIL\""
```

#### 5.2 下载静态 jq

```bash
SSH_CMD "[ -f /opt/tech-stack/cicd/jq-static ] && /opt/tech-stack/cicd/jq-static --version 2>/dev/null && echo 'JQ_EXISTS' || echo 'JQ_MISSING'"
```

- 返回 `JQ_EXISTS` → 跳过
- 返回 `JQ_MISSING` → 下载（按优先级尝试）：

```bash
# 方案1：CN GitHub 代理（推荐，国内可达）
SSH_CMD "curl -sfL --connect-timeout 15 \
  https://mirror.ghproxy.com/https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64 \
  -o /opt/tech-stack/cicd/jq-static && \
  chmod +x /opt/tech-stack/cicd/jq-static && echo DOWNLOAD_OK || echo DOWNLOAD_FAIL"
```

若返回 DOWNLOAD_FAIL，尝试直连 GitHub：

```bash
# 方案2：直连 GitHub（宿主机有外网时可用）
SSH_CMD "curl -sfL --connect-timeout 10 \
  https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64 \
  -o /opt/tech-stack/cicd/jq-static && \
  chmod +x /opt/tech-stack/cicd/jq-static && echo DOWNLOAD_OK || echo DOWNLOAD_FAIL"
```

若仍失败，借助 Maven 容器下载：

```bash
# 方案3：Maven 容器（容器网络路由与宿主机不同，可绕过部分限制）
SSH_CMD "docker run --rm \
  -v /opt/tech-stack/cicd:/opt/tech-stack/cicd \
  maven:3.9-eclipse-temurin-21 bash -c \
  \"curl -sfL --connect-timeout 15 \
    https://mirror.ghproxy.com/https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64 \
    -o /opt/tech-stack/cicd/jq-static && \
    chmod +x /opt/tech-stack/cicd/jq-static && echo DOWNLOAD_OK || echo DOWNLOAD_FAIL\""
```

#### 5.3 下载 docker 静态二进制

```bash
SSH_CMD "[ -f /opt/tech-stack/cicd/docker-static ] && /opt/tech-stack/cicd/docker-static --version 2>/dev/null && echo 'DOCKER_EXISTS' || echo 'DOCKER_MISSING'"
```

- 返回 `DOCKER_EXISTS` → 跳过
- 返回 `DOCKER_MISSING` → 复制宿主机 docker binary（宿主机已安装 docker，直接复制即可）：

```bash
SSH_CMD "cp /usr/bin/docker /opt/tech-stack/cicd/docker-static && chmod +x /opt/tech-stack/cicd/docker-static && /opt/tech-stack/cicd/docker-static --version && echo COPY_OK"
```

> ⚠️ docker binary 与 kubectl/jq 不同：docker 并非完全静态链接，但宿主机（CentOS/RHEL）与 CI 容器（Ubuntu LTS）的 glibc 版本兼容，复制宿主机 binary 可正常工作。

#### 5.4 下载 OTel Java Agent

> **用途**：OpenTelemetry Java Agent 用于 Spring Boot 2.x 老系统的链路追踪和日志采集（方案 B 兜底）。
>
> **设计说明**：Agent 单独存放于 `/opt/tech-stack/cicd/`，通过 config.toml volumes 挂载到 CI Job 容器，而非集成到基础镜像。优点：
> - 一个 Agent 跨 JDK 8~21 版本通用
> - 更新 Agent 只需替换一个文件，无需重建基础镜像
> - 与 app.sh/settings.xml/kubectl-bin 管理方式一致

```bash
SSH_CMD "[ -f /opt/tech-stack/cicd/opentelemetry-javaagent.jar ] && echo 'OTEL_AGENT_EXISTS' || echo 'OTEL_AGENT_MISSING'"
```

- 返回 `OTEL_AGENT_EXISTS` → 跳过
- 返回 `OTEL_AGENT_MISSING` → 下载：

```bash
# 方案1：CN GitHub 代理（推荐，国内可达）
SSH_CMD "curl -sfL --connect-timeout 15 \
  https://mirror.ghproxy.com/https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.26.1/opentelemetry-javaagent.jar \
  -o /opt/tech-stack/cicd/opentelemetry-javaagent.jar && echo DOWNLOAD_OK || echo DOWNLOAD_FAIL"
```

若返回 DOWNLOAD_FAIL，尝试直连 GitHub：

```bash
# 方案2：直连 GitHub（宿主机有外网时可用）
SSH_CMD "curl -sfL --connect-timeout 15 \
  https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.26.1/opentelemetry-javaagent.jar \
  -o /opt/tech-stack/cicd/opentelemetry-javaagent.jar && echo DOWNLOAD_OK || echo DOWNLOAD_FAIL"
```

若仍失败，借助 Maven 容器下载：

```bash
# 方案3：Maven 容器（容器网络可绕过部分限制）
SSH_CMD "docker run --rm \
  -v /opt/tech-stack/cicd:/opt/tech-stack/cicd \
  maven:3.9-eclipse-temurin-21 bash -c \
  \"curl -sfL --connect-timeout 30 \
    https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.26.1/opentelemetry-javaagent.jar \
    -o /opt/tech-stack/cicd/opentelemetry-javaagent.jar && echo DOWNLOAD_OK || echo DOWNLOAD_FAIL\""
```

**验证 Agent 可用**：

```bash
SSH_CMD "ls -lh /opt/tech-stack/cicd/opentelemetry-javaagent.jar"
```

预期输出文件大小约 60~80 MB。

#### 5.5 在 CI 容器内验证（模拟实际 Pipeline 环境）

```bash
SSH_CMD "docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /opt/tech-stack/cicd/kubectl-bin:/usr/local/bin/kubectl:ro \
  -v /opt/tech-stack/cicd/jq-static:/usr/local/bin/jq:ro \
  -v /opt/tech-stack/cicd/docker-static:/usr/local/bin/docker:ro \
  maven:3.9-eclipse-temurin-21 bash -c \
  \"kubectl version --client && jq --version && docker --version && echo TOOLS_OK\""
```

### 步骤 6：上传 app.sh 脚本

> **用途**：CI Job 部署脚本，从 Apollo 读取配置，构建镜像，部署到 K3s。
>
> **⚠️ 敏感信息**：app.sh 中包含 `HARBOR_PASSWORD="CHANGE_ME_HARBOR_PASSWORD"` 占位符，**上传前必须替换为实际密码**。

#### 6.0 生产环境上云模式确认（仅 `RUNNER_ENV=prod` 时执行）

> **非生产环境（nonprod）请跳过此子步骤**：dev / sit / fat / uat 始终使用本项目部署的中间件，无上云场景，无需确认。

**背景**：标准 `references/app.sh` 假设业务 Pod 通过内网 infra-nginx 访问 Apollo Config Service（`apollo.meta=http://apollo-config-prod.renew.com`，不带端口由 nginx :80 → :8605 反代）。如果生产 K3s 已上云到公有云 VPC 且由 PrivateZone 接管 DNS，必须改为直连模式（`apollo.meta=http://apollo-config-prod.renew.com:8605`，带端口直连）。否则**跨域 VPN 故障 → 新 Pod 拉不到 Apollo 配置 → K3s 自愈 / HPA / 滚动更新全失败 → 业务雪崩**。详见 [cloud-migration-reference.md §4.1](../../cloud-migration-reference.md#41-dns-层阿里云-privatezone-接管)。

**执行流程**：

通过 AskUserQuestion 询问用户：

- 问题：本次生产 K3s 集群所连的**中间件 / Apollo Config Service** 是否已上云到公有云 VPC？
- 选项 A：**否，仍由本项目部署的中间件提供**（标准架构）
  → 继续执行后续步骤 6.1~6.2，使用 `references/app.sh` 默认值（`APOLLO_CLOUD_MIGRATED="false"`）
- 选项 B：**是，已上云到阿里云 / 腾讯云等公有云 VPC**
  → **中止本步骤**，提示用户按下列清单先行操作，完成后重新执行 `setup-gitlab-runner start --env prod`：
    1. 备份当前 `references/app.sh`（`cp app.sh app.sh.bak`）
    2. 参考 `references/app-fulong-ref.sh`（已知公有云适配实现），按云端架构重写 `references/app.sh`：
       - 将配置区 `APOLLO_CLOUD_MIGRATED="false"` 改为 `"true"`
       - 按需替换 `HARBOR_URL` 为云镜像仓库（如 ACR）域名
       - 检查 NEXUS / OTel / 中间件域名与端口是否需要适配 PrivateZone 直连规则
       - 其他云厂商特定调整参考 `app-fulong-ref.sh`
    3. 重新执行本 action

#### 6.1 从 .env 读取 Harbor 密码

```bash
# 从 skill 目录的 .env 读取密码
HARBOR_PASSWORD=$(grep '^HARBOR_PASSWORD=' ${CLAUDE_SKILL_DIR}/references/.env | cut -d'=' -f2)

# 校验密码是否已配置
if [ -z "${HARBOR_PASSWORD}" ] || [ "${HARBOR_PASSWORD}" = "CHANGE_ME_HARBOR_PASSWORD" ]; then
  echo "[ERROR] Harbor 密码未配置"
  echo "[HINT] 请编辑 references/.env 文件，设置 HARBOR_PASSWORD"
  exit 1
fi
```

#### 6.2 替换密码后上传

```bash
# 本地临时替换密码后上传
sed "s/CHANGE_ME_HARBOR_PASSWORD/${HARBOR_PASSWORD}/g" ${CLAUDE_SKILL_DIR}/references/app.sh > /tmp/app.sh

# 上传
scp -P ${SSH_PORT:-22} /tmp/app.sh ${SSH_USER:-root}@${HOST}:/opt/tech-stack/cicd/app.sh

# 设置可执行权限
SSH_CMD "chmod +x /opt/tech-stack/cicd/app.sh"

# 清理临时文件
rm /tmp/app.sh
```

**验证密码已替换**：

```bash
SSH_CMD "grep 'HARBOR_PASSWORD=' /opt/tech-stack/cicd/app.sh | head -1"
```

预期输出不包含 `CHANGE_ME_`。

| 配置项 | 说明 |
|--------|------|
| `HARBOR_URL` | Harbor 地址，默认 `harbor.renew.com` |
| `HARBOR_PROJECT` | Harbor 项目，默认 `library` |
| `HARBOR_PASSWORD` | Harbor 密码，从 `.env` 读取 |

### 步骤 7：上传 Maven settings.xml

> **用途**：配置 Nexus 私服镜像，加速依赖下载；支持环境变量注入敏感信息（密码）。
>
> **文件位置**：`/opt/tech-stack/cicd/settings.xml` → 挂载到 CI 容器 `/root/.m2/settings.xml`
>
> **⚠️ 敏感信息**：settings.xml 中包含 `CHANGE_ME_NEXUS_PASSWORD` 占位符，**上传前必须替换为实际密码**。

#### 7.1 从 .env 读取 Nexus 密码

```bash
# 从 skill 目录的 .env 读取密码
NEXUS_PASSWORD=$(grep '^NEXUS_PASSWORD=' ${CLAUDE_SKILL_DIR}/references/.env | cut -d'=' -f2)

# 校验密码是否已配置
if [ -z "${NEXUS_PASSWORD}" ] || [ "${NEXUS_PASSWORD}" = "CHANGE_ME_NEXUS_PASSWORD" ]; then
  echo "[ERROR] Nexus 密码未配置"
  echo "[HINT] 请编辑 references/.env 文件，设置 NEXUS_PASSWORD"
  exit 1
fi
```

#### 7.2 替换密码后上传

```bash
# 本地临时替换密码后上传
sed "s/CHANGE_ME_NEXUS_PASSWORD/${NEXUS_PASSWORD}/g" ${CLAUDE_SKILL_DIR}/references/settings.xml > /tmp/settings.xml

# 上传
scp -P ${SSH_PORT:-22} /tmp/settings.xml ${SSH_USER:-root}@${HOST}:/opt/tech-stack/cicd/settings.xml

# 清理临时文件
rm /tmp/settings.xml
```

**验证文件上传**：

```bash
SSH_CMD "ls -la /opt/tech-stack/cicd/settings.xml"
```

**settings.xml 配置说明**：

| 配置项 | 说明 |
|--------|------|
| `<mirrors>` | 镜像所有 Maven 请求到 Nexus `maven-public` 仓库 |
| `<servers>` | Nexus 认证配置，密码从 `.env` 读取 |
| `<localRepository>` | 本地仓库路径，CI 环境默认使用项目内 `.m2/repository` |

### 步骤 8：配置 kubeconfig

> **关键**：Runner 需要远程访问 K3s API，必须配置 kubeconfig。

#### 8.1 检查 K3s 是否在同一机器

```bash
SSH_CMD "ls /etc/rancher/k3s/k3s.yaml 2>/dev/null && echo 'K3S_LOCAL' || echo 'K3S_REMOTE'"
```

#### 8.2 如果 K3s 在同一机器

```bash
# 复制 kubeconfig 到 cicd 目录
SSH_CMD "cp /etc/rancher/k3s/k3s.yaml /opt/tech-stack/cicd/kubeconfig"

# 修改 server 地址（从 127.0.0.1 改为实际 IP）
SSH_CMD "sed -i 's/127.0.0.1/${HOST}/g' /opt/tech-stack/cicd/kubeconfig"

# 设置权限
SSH_CMD "chmod 600 /opt/tech-stack/cicd/kubeconfig"
```

#### 8.3 如果 K3s 在不同机器

需要从 K3s master 复制 kubeconfig：

```bash
# 在 K3s master 导出
ssh root@<k3s-master> "cat /etc/rancher/k3s/k3s.yaml" > ./kubeconfig

# 修改 server 地址
sed -i 's/127.0.0.1/<k3s-master-ip>/g' ./kubeconfig

# 上传到 Runner 机器
scp ./kubeconfig root@${HOST}:/opt/tech-stack/cicd/kubeconfig
```

### 步骤 9：推送基础镜像到 Harbor

> **关键**：CI/CD 构建需要基础镜像，必须先推送到 Harbor。支持多语言多版本。
>
> **密码**：使用步骤 6.1 获取的 `${HARBOR_PASSWORD}`

#### 9.1 检查 Harbor 中基础镜像是否存在

```bash
SSH_CMD "curl -s -o /dev/null -w '%{http_code}' -u admin:${HARBOR_PASSWORD} \
  http://harbor.renew.com/api/v2.0/projects/library/repositories/jdk/artifacts \
  2>/dev/null"
```

- 返回 200 → 镜像已存在，跳过推送
- 返回 404 → 需要推送基础镜像

#### 9.2 登录 Harbor

```bash
SSH_CMD "echo ${HARBOR_PASSWORD} | docker login -u admin --password-stdin harbor.renew.com"
```

#### 9.3 推送 JDK 基础镜像（多版本）

```bash
# JDK 8
SSH_CMD "docker pull docker.1ms.run/eclipse-temurin:8-jdk-alpine 2>/dev/null || docker pull eclipse-temurin:8-jdk-alpine"
SSH_CMD "docker tag eclipse-temurin:8-jdk-alpine harbor.renew.com/library/jdk:8 && docker push harbor.renew.com/library/jdk:8"
SSH_CMD "docker rmi eclipse-temurin:8-jdk-alpine harbor.renew.com/library/jdk:8 2>/dev/null || true"

# JDK 11
SSH_CMD "docker pull docker.1ms.run/eclipse-temurin:11-jdk-alpine 2>/dev/null || docker pull eclipse-temurin:11-jdk-alpine"
SSH_CMD "docker tag eclipse-temurin:11-jdk-alpine harbor.renew.com/library/jdk:11 && docker push harbor.renew.com/library/jdk:11"
SSH_CMD "docker rmi eclipse-temurin:11-jdk-alpine harbor.renew.com/library/jdk:11 2>/dev/null || true"

# JDK 17
SSH_CMD "docker pull docker.1ms.run/eclipse-temurin:17-jdk-alpine 2>/dev/null || docker pull eclipse-temurin:17-jdk-alpine"
SSH_CMD "docker tag eclipse-temurin:17-jdk-alpine harbor.renew.com/library/jdk:17 && docker push harbor.renew.com/library/jdk:17"
SSH_CMD "docker rmi eclipse-temurin:17-jdk-alpine harbor.renew.com/library/jdk:17 2>/dev/null || true"

# JDK 21（默认）
SSH_CMD "docker pull docker.1ms.run/eclipse-temurin:21-jdk-alpine 2>/dev/null || docker pull eclipse-temurin:21-jdk-alpine"
SSH_CMD "docker tag eclipse-temurin:21-jdk-alpine harbor.renew.com/library/jdk:21 && docker push harbor.renew.com/library/jdk:21"
SSH_CMD "docker rmi eclipse-temurin:21-jdk-alpine harbor.renew.com/library/jdk:21 2>/dev/null || true"
```

#### 9.4 推送 Nginx 基础镜像（前端项目）

```bash
SSH_CMD "docker pull docker.1ms.run/nginx:1.27-alpine 2>/dev/null || docker pull nginx:1.27-alpine"
SSH_CMD "docker tag nginx:1.27-alpine harbor.renew.com/library/nginx:1.27 && docker push harbor.renew.com/library/nginx:1.27"
SSH_CMD "docker rmi nginx:1.27-alpine harbor.renew.com/library/nginx:1.27 2>/dev/null || true"
```

#### 9.5 推送 Python 基础镜像（多版本）

```bash
# Python 3.9
SSH_CMD "docker pull docker.1ms.run/python:3.9-slim 2>/dev/null || docker pull python:3.9-slim"
SSH_CMD "docker tag python:3.9-slim harbor.renew.com/library/python:3.9 && docker push harbor.renew.com/library/python:3.9"
SSH_CMD "docker rmi python:3.9-slim harbor.renew.com/library/python:3.9 2>/dev/null || true"

# Python 3.10
SSH_CMD "docker pull docker.1ms.run/python:3.10-slim 2>/dev/null || docker pull python:3.10-slim"
SSH_CMD "docker tag python:3.10-slim harbor.renew.com/library/python:3.10 && docker push harbor.renew.com/library/python:3.10"
SSH_CMD "docker rmi python:3.10-slim harbor.renew.com/library/python:3.10 2>/dev/null || true"

# Python 3.11（默认）
SSH_CMD "docker pull docker.1ms.run/python:3.11-slim 2>/dev/null || docker pull python:3.11-slim"
SSH_CMD "docker tag python:3.11-slim harbor.renew.com/library/python:3.11 && docker push harbor.renew.com/library/python:3.11"
SSH_CMD "docker rmi python:3.11-slim harbor.renew.com/library/python:3.11 2>/dev/null || true"

# Python 3.12
SSH_CMD "docker pull docker.1ms.run/python:3.12-slim 2>/dev/null || docker pull python:3.12-slim"
SSH_CMD "docker tag python:3.12-slim harbor.renew.com/library/python:3.12 && docker push harbor.renew.com/library/python:3.12"
SSH_CMD "docker rmi python:3.12-slim harbor.renew.com/library/python:3.12 2>/dev/null || true"
```

#### 9.6 验证基础镜像

```bash
SSH_CMD "curl -s -u admin:${HARBOR_PASSWORD} \
  'http://harbor.renew.com/api/v2.0/projects/library/repositories' | \
  jq -r '.[].name'"
```

预期输出包含：
- `library/jdk` (8/11/17/21)
- `library/nginx` (1.27)
- `library/python` (3.9/3.10/3.11/3.12)

---

## 阶段 C：启动 Runner 容器

### 步骤 10：上传 Runner 配置到 /opt/tech-stack/gitlab-runner/

```bash
# 密码模式
sshpass -p "${SSH_PASSWORD}" scp -r -P ${SSH_PORT:-22} \
  ${CLAUDE_SKILL_DIR}/references/docker-compose.yml \
  ${CLAUDE_SKILL_DIR}/references/.env.example \
  ${CLAUDE_SKILL_DIR}/references/config \
  ${SSH_USER:-root}@${HOST}:/opt/tech-stack/gitlab-runner/

# 密钥模式
scp -i ${SSH_KEY_PATH} -r -P ${SSH_PORT:-22} \
  ${CLAUDE_SKILL_DIR}/references/docker-compose.yml \
  ${CLAUDE_SKILL_DIR}/references/.env.example \
  ${CLAUDE_SKILL_DIR}/references/config \
  ${SSH_USER:-root}@${HOST}:/opt/tech-stack/gitlab-runner/
```

> `app.sh`、`settings.xml` **不上传到 gitlab-runner 目录**（它们属于阶段 B 的产物，已在 `/opt/tech-stack/cicd/` 就位）。

### 步骤 11：检查远程 .env 文件

```bash
SSH_CMD "ls /opt/tech-stack/gitlab-runner/.env 2>/dev/null || \
  cp /opt/tech-stack/gitlab-runner/.env.example /opt/tech-stack/gitlab-runner/.env"
```

- 若 .env 含 `CHANGE_ME_` → 提示用户修改后再继续（特别是 `RUNNER_REGISTRATION_TOKEN`）

### 步骤 12：确保配置与缓存目录存在

```bash
SSH_CMD "mkdir -p /opt/tech-stack/gitlab-runner/config /opt/tech-stack/gitlab-runner/cache"
```

### 步骤 13：确保 Runner 镜像可用

> **推荐**：使用内网 Harbor 镜像，不依赖外网。镜像地址 `harbor.renew.com/library/gitlab-runner:alpine` 已写入 docker-compose.yml。

**前置条件**：目标机器 Docker 已配置 `insecure-registries: ["harbor.renew.com"]`（HTTP registry 必需）。

**实现方式（paramiko + JSON 字典合并，幂等）**：

1. **读取**：`sftp.get('/etc/docker/daemon.json', local_tmp)` 拉取现有 daemon.json
   - 文件不存在 → 视作空配置 `{}`
   - 文件存在但解析失败 → 报错退出，提示用户手动检查（避免覆盖未知格式）
2. **合并**：Python `json.load(...)` → 取 `data.setdefault("insecure-registries", [])` → 若 `harbor.renew.com` 不在列表中则 `append` → 去重保序
3. **回写**：`sftp.put(local_tmp, '/etc/docker/daemon.json')` 上传，权限保持 `0644`
4. **重启**：`SSH_CMD "systemctl restart docker"`，等待 Docker 就绪（`docker info` 探活）

> **关键约束**：
> - 严禁使用 `cat > daemon.json << EOF ...其他配置... EOF`（`...其他配置...` 会被原样写入文件，破坏 JSON）
> - 严禁使用 `sftp.open('w')` 字符串写入（`${VAR}` 会被吞掉），必须本地构造完整 JSON 后用 `sftp.put` 文件复制
> - 合并必须幂等：重复执行不应产生重复条目或破坏其他已配置字段（如 `log-driver` / `default-runtime`）

**伪代码示例**：

```python
import json, paramiko
remote_path = '/etc/docker/daemon.json'
local_tmp = '/tmp/daemon.json.merged'

# 1. 读取（不存在则空字典）
try:
    with sftp.open(remote_path, 'r') as f:
        data = json.load(f)
except (FileNotFoundError, IOError):
    data = {}
except json.JSONDecodeError:
    raise SystemExit(f"[ERROR] 现有 {remote_path} JSON 解析失败，请手动检查后重试")

# 2. 合并（幂等去重）
registries = data.setdefault("insecure-registries", [])
if "harbor.renew.com" not in registries:
    registries.append("harbor.renew.com")

# 3. 本地写文件 → sftp 上传
with open(local_tmp, 'w') as f:
    json.dump(data, f, indent=2)
sftp.put(local_tmp, remote_path)
sftp.chmod(remote_path, 0o644)

# 4. 重启 Docker
SSH_CMD("systemctl restart docker && sleep 3 && docker info > /dev/null")
```

**镜像拉取**：

```bash
# 登录 Harbor（可选，library 项目公开时可不登录）
SSH_CMD "echo ${HARBOR_PASSWORD} | docker login -u admin --password-stdin harbor.renew.com"

# 拉取镜像
SSH_CMD "docker pull harbor.renew.com/library/gitlab-runner:alpine 2>&1 | tail -3"
```

- 拉取成功 → 继续
- Harbor 不可用 → 回退到公网 mirror：

```bash
# 尝试 docker.1ms.run（国内可用）
SSH_CMD "docker pull docker.1ms.run/gitlab/gitlab-runner:alpine"
SSH_CMD "docker tag docker.1ms.run/gitlab/gitlab-runner:alpine harbor.renew.com/library/gitlab-runner:alpine"
```

### 步骤 14：远程执行 docker compose up

```bash
SSH_CMD "cd /opt/tech-stack/gitlab-runner && docker compose up -d"
```

### 步骤 15：远程健康检查（最多 30 秒）

```bash
SSH_CMD "for i in \$(seq 1 6); do docker exec tech-gitlab-runner-${RUNNER_ENV} gitlab-runner --version > /dev/null 2>&1 && echo READY && break; echo \"等待...\$i/6\"; sleep 5; done"
```

---

## 阶段 D：整体验证与下一步

### 步骤 16：验证 Runner 挂载到 cicd 目录

```bash
SSH_CMD "docker exec tech-gitlab-runner-${RUNNER_ENV} ls -la /opt/tech-stack/cicd/"
```

预期输出包含 `app.sh`、`settings.xml`、`kubeconfig`、`kubectl-bin`、`jq-static`、`docker-static`。

### 步骤 17：展示配置信息与下一步

```
✅ CI/CD 执行环境就绪

【/opt/tech-stack/cicd/】（Runner 挂载依赖）
├── app.sh           # CI Job 部署脚本
├── settings.xml     # Maven 配置（Nexus 私服镜像）
├── kubeconfig       # K3s 访问凭证
├── kubectl-bin      → 挂载为 /usr/local/bin/kubectl（静态二进制）
├── jq-static        → 挂载为 /usr/local/bin/jq（静态二进制，无 so 依赖）
├── docker-static    → 挂载为 /usr/local/bin/docker（docker CLI）
└── opentelemetry-javaagent.jar → 挂载为 /opt/otel/opentelemetry-javaagent.jar（OTel Agent v2.26.1）

【/opt/tech-stack/gitlab-runner/】（Runner 容器）
├── docker-compose.yml
├── .env                # 注册 Token 等
├── config/             # config.toml 由 register 自动生成
└── cache/              # CI 缓存

【Harbor 基础镜像】
- library/jdk: 8, 11, 17, 21
- library/nginx: 1.27
- library/python: 3.9, 3.10, 3.11, 3.12

⚠️ Runner 尚未注册到 GitLab，请按顺序执行：

1. 在 GitLab 获取 Registration Token：
   http://gitlab.renew.com → Settings → CI/CD → Runners → New Project Runner
   复制 glrt- 开头的 Token

2. 写入 Token：
   ssh ${SSH_USER:-root}@${HOST} "vi /opt/tech-stack/gitlab-runner/.env"
   # 设置 RUNNER_REGISTRATION_TOKEN=glrt-xxxxxxxx

3. 注册 Runner：
   /setup-gitlab-runner register --host ${HOST}

4. 验证环境：
   /setup-gitlab-runner verify --host ${HOST}

5. （可选）端到端验证：
   /setup-cicd demo --host ${HOST}
```

---

## 部署报告输出

> 部署完成后，必须在项目 `env/` 目录下生成或更新部署报告文件 `env/gitlab-runner.md`。

报告模板：

```markdown
# GitLab Runner（CI/CD 执行环境）— 部署报告

| 项目 | 值 |
|------|-----|
| 部署日期 | YYYY-MM-DD |
| 目标机器 | <IP> |
| Runner 部署目录 | /opt/tech-stack/gitlab-runner/ |
| CI Job 环境目录 | /opt/tech-stack/cicd/ |
| 容器名称 | tech-gitlab-runner-${RUNNER_ENV}（nonprod / prod） |
| 镜像 | harbor.renew.com/library/gitlab-runner:alpine |
| Runner 状态 | 未注册 / 已注册 |

## 端口

| 端口 | 用途 |
|------|------|
| 无暴露端口 | Runner 主动连接 GitLab，无需入站端口 |

## /opt/tech-stack/cicd/ 文件清单

| 文件 | 用途 |
|------|------|
| app.sh | CI/CD 部署脚本 |
| settings.xml | Maven 配置（Nexus 私服镜像） |
| kubeconfig | K3s 访问凭证 |
| kubectl-bin | 静态 kubectl v1.32.0 |
| jq-static | 静态 jq 1.7.1 |
| docker-static | docker CLI（宿主机复制） |
| opentelemetry-javaagent.jar | OTel Java Agent v2.26.1（Spring Boot 2.x 兜底） |

## CI Job 挂载配置

| 宿主机路径 | 容器内路径 | 用途 |
|-----------|-----------|------|
| /var/run/docker.sock | /var/run/docker.sock | 构建/推送镜像 |
| /opt/tech-stack/cicd | /opt/tech-stack/cicd | app.sh、kubeconfig |
| cicd/kubectl-bin | /usr/local/bin/kubectl | 静态 kubectl |
| cicd/jq-static | /usr/local/bin/jq | 静态 jq |
| cicd/docker-static | /usr/local/bin/docker | docker CLI |
| cicd/settings.xml | /root/.m2/settings.xml | Maven 配置 |
| cicd/opentelemetry-javaagent.jar | /opt/otel/opentelemetry-javaagent.jar | OTel Agent |

## Harbor 基础镜像

| 镜像 | 版本 | 用途 |
|------|------|------|
| harbor.renew.com/library/jdk | 8, 11, 17, 21 | Java 应用 |
| harbor.renew.com/library/nginx | 1.27 | 前端应用 |
| harbor.renew.com/library/python | 3.9, 3.10, 3.11, 3.12 | Python 应用 |

## K3s 连接

| 项目 | 值 |
|------|-----|
| K3s API | https://<HOST>:6443 |
| kubeconfig | /opt/tech-stack/cicd/kubeconfig |

> namespace 和 harbor-registry Secret 由 app.sh 在首次 Pipeline 时自动创建（幂等）。

## Runner 配置

| 配置项 | 值 |
|--------|-----|
| GitLab URL | http://gitlab.renew.com |
| Executor | docker |
| 默认镜像 | maven:3.9-eclipse-temurin-21 |
| 并发数 | 2 |

## 验证命令

```bash
# Runner 是否就绪
docker exec tech-gitlab-runner-${RUNNER_ENV} gitlab-runner --version

# cicd 目录是否挂载到 Runner
docker exec tech-gitlab-runner-${RUNNER_ENV} ls /opt/tech-stack/cicd/

# K3s 连接
kubectl --kubeconfig=/opt/tech-stack/cicd/kubeconfig get nodes

# app.sh 可执行
/opt/tech-stack/cicd/app.sh
```

## 备注

- Runner 需要先注册才能执行作业（`/setup-gitlab-runner register`）
- app.sh、settings.xml 现归属 setup-gitlab-runner/references/（apollo-tech-common.properties 仍归 setup-cicd）
- 静态 kubectl/jq/docker 通过 config.toml volumes 挂载到 CI Job 容器
```

报告文件路径：`<project_root>/env/gitlab-runner.md`
