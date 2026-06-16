# GitLab Runner — CI/CD 执行器 + 执行环境一站式部署

GitLab Runner 是 GitLab CI/CD 的执行组件，负责执行 `.gitlab-ci.yml` 中定义的流水线作业。本 skill 采用 Docker 方式部署，并**一站式**准备 CI Job 执行所需的全部基础设施（app.sh、kubeconfig、静态工具、基础镜像）。

---

## 特性

- **一站式部署**：单条 `start` 命令完成静态工具下载、app.sh/settings.xml 上传、kubeconfig 配置、基础镜像推送、Runner 容器启动
- **Docker Executor**：每个 CI 作业在独立容器中执行，环境隔离
- **Docker Socket 挂载**：CI 作业可构建/推送镜像
- **镜像缓存**：支持 Maven/NPM 等依赖缓存，加速构建
- **多标签支持**：通过标签匹配特定类型的作业

---

## 快速开始

### 1. 获取 Registration Token

1. 登录 GitLab → Settings → CI/CD → Runners
2. 点击 "New Project Runner"
3. 选择 Platform（Linux）、Tags（可选）
4. 点击 "Create runner"
5. 复制生成的 Token（glrt- 开头）

### 2. 部署 Runner + CI Job 执行环境

```bash
# 安装 skill
cd setup-gitlab-runner && bash install.sh

# 一站式部署（Runner + app.sh + kubeconfig + 基础镜像）
/setup-gitlab-runner start --host <IP> --user root --key ~/.ssh/id_rsa

# 编辑 .env 设置 Token
ssh root@<IP> "vi /opt/tech-stack/gitlab-runner/.env"

# 注册 Runner
/setup-gitlab-runner register --host <IP> --user root --key ~/.ssh/id_rsa

# 验证环境（Runner + cicd 目录 + K3s + Harbor）
/setup-gitlab-runner verify --host <IP> --user root --key ~/.ssh/id_rsa
```

---

## CI Job 执行环境（/opt/tech-stack/cicd/）

`start` action 除了启动 Runner 容器外，还会在 `/opt/tech-stack/cicd/` 准备好 CI Job 所需的全部依赖。这些文件通过 config.toml volumes 挂载到每个 CI Job 容器内。

### 文件清单

| 宿主机路径 | 容器内挂载 | 用途 |
|-----------|-----------|------|
| `/opt/tech-stack/cicd/app.sh` | `/opt/tech-stack/cicd/app.sh` | CI Job 部署脚本 |
| `/opt/tech-stack/cicd/settings.xml` | `/root/.m2/settings.xml` | Maven 配置（Nexus 镜像） |
| `/opt/tech-stack/cicd/kubeconfig` | `/opt/tech-stack/cicd/kubeconfig` | K3s 访问凭证 |
| `/opt/tech-stack/cicd/kubectl-bin` | `/usr/local/bin/kubectl` | 静态 kubectl v1.32.0 |
| `/opt/tech-stack/cicd/jq-static` | `/usr/local/bin/jq` | 静态 jq 1.7.1 |
| `/opt/tech-stack/cicd/docker-static` | `/usr/local/bin/docker` | docker CLI |
| `/opt/tech-stack/cicd/opentelemetry-javaagent.jar` | `/opt/otel/opentelemetry-javaagent.jar` | OTel Java Agent v2.26.1（Spring Boot 2.x 兜底） |

### 为什么必须用静态二进制

- K3s 机器上 `/usr/local/bin/kubectl` 是 **k3s 符号链接**，挂载进 CI 容器后执行的是 k3s 二进制，行为异常
- yum/apt 安装的 jq 是 **动态链接**，依赖 `libjq.so.1`，挂载到 Ubuntu/Debian CI 容器会找不到 so 文件

### K3s 预准备

`start` 同时会创建：

- `fat` namespace
- `harbor-registry` Secret（在 Pipeline 对应 namespace 下，由 app.sh 首次部署时自动创建）

其他 namespace（sit/uat/prod）的 Secret 由 app.sh 在首次 Pipeline 时自动创建，幂等。

### Harbor 基础镜像

| 镜像 | 版本 | 用途 |
|------|------|------|
| `harbor.renew.com/library/jdk` | 8, 11, 17, 21 | Java 应用 |
| `harbor.renew.com/library/nginx` | 1.27 | 前端应用 |
| `harbor.renew.com/library/python` | 3.9, 3.10, 3.11, 3.12 | Python 应用 |

---

## 配置说明

### .env 关键配置

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `GITLAB_URL` | GitLab 实例地址 | `http://gitlab.renew.com` |
| `RUNNER_REGISTRATION_TOKEN` | 注册 Token（glrt- 格式） | 必须从 GitLab 获取 |
| `RUNNER_NAME` | Runner 名称 | `gitlab-runner-01` |
| `RUNNER_DOCKER_IMAGE` | 默认镜像 | `maven:3.9-eclipse-temurin-21` |
| `RUNNER_CONCURRENT` | 并发作业数（注册后写入 config.toml） | `2` |

> **Runner 18.x 说明**：`RUNNER_TAGS`、`RUNNER_RUN_UNTAGGED` 等已从 register 命令移除，在 GitLab UI 中配置（Settings → CI/CD → Runners → 编辑 Runner）。

### 镜像拉取说明

docker-compose.yml 使用内网 Harbor 镜像 `harbor.renew.com/library/gitlab-runner:alpine`，需先：

1. **配置 insecure-registries**（Harbor 使用 HTTP）：
   ```json
   // /etc/docker/daemon.json
   {
     "insecure-registries": ["harbor.renew.com"]
   }
   ```
   修改后执行 `systemctl restart docker`

2. **拉取镜像**：
   ```bash
   docker pull harbor.renew.com/library/gitlab-runner:alpine
   ```

**公网 Mirror 备选**（Harbor 不可用时）：

| Mirror | 可用性 | 备注 |
|--------|--------|------|
| `docker.1ms.run` | ✅ 推荐 | 国内可用 |
| `docker.m.daocloud.io` | ❌ | gitlab-runner 返回 denied |
| `docker.xuanyuan.me` | ⚠️ 不稳定 | 免费节点经常繁忙 |

### config.toml 示例

```toml
concurrent = 2

[[runners]]
  name = "gitlab-runner-01"
  url = "http://gitlab.renew.com"
  executor = "docker"
  [runners.docker]
    image = "maven:3.9-eclipse-temurin-21"
    privileged = false
    pull_policy = ["if-not-present"]
    volumes = ["/cache", "/var/run/docker.sock:/var/run/docker.sock"]
```

---

## 常见使用场景

### 1. Maven 构建

```yaml
# .gitlab-ci.yml
build:
  stage: build
  image: maven:3.9-eclipse-temurin-21
  script:
    - mvn clean package -DskipTests
  artifacts:
    paths:
      - target/*.jar
```

### 2. Docker 镜像构建（Socket 挂载方式）

> Runner 已挂载宿主机 Docker socket，CI 作业直接使用宿主机 Docker 引擎，无需 DinD service。
> 前提：宿主机 Docker 已配置 `insecure-registries: ["harbor.renew.com"]`。

```yaml
# .gitlab-ci.yml
docker-build:
  stage: build
  image: docker:24
  script:
    - docker login -u $HARBOR_USER -p $HARBOR_PASS harbor.renew.com
    - docker build -t harbor.renew.com/myproject/myapp:$CI_COMMIT_SHA .
    - docker push harbor.renew.com/myproject/myapp:$CI_COMMIT_SHA
```

### 3. 部署到 Kubernetes

```yaml
# .gitlab-ci.yml
deploy:
  stage: deploy
  image: bitnami/kubectl:latest
  script:
    - kubectl set image deployment/myapp myapp=harbor.renew.com/myproject/myapp:$CI_COMMIT_SHA
```

---

## 故障排查

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| Runner 不执行作业 | 未配置标签匹配 | 检查 tags 或启用 "Run untagged jobs" |
| Docker 命令权限不足 | socket 权限 | `usermod -aG docker gitlab-runner` 并重建容器（生产）；临时：`chmod 666 /var/run/docker.sock` |
| 镜像拉取超时 | 网络问题 | 配置镜像加速器 |
| GitLab 连接失败 | DNS 解析问题 | 配置 DNS 或添加 hosts |

---

## 参考

- [app.sh 部署规范](references/app-sh-spec.md) — CI Job 部署脚本生成的 K8s 资源结构说明
- [GitLab Runner 官方文档](https://docs.gitlab.com/runner/)
- [Docker Executor 配置](https://docs.gitlab.com/runner/executors/docker.html)
- [GitLab CI/CD 配置](https://docs.gitlab.com/ee/ci/yaml/)
