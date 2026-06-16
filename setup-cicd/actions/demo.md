# action: demo — CI/CD 端到端验证

> 本 action 用于验证整个 CI/CD 环境是否已通顺。通过推送 Demo 项目到 GitLab，触发 Pipeline 构建、部署到 K3s，验证完整链路。

## 架构总览

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CI/CD 架构                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐    │
│  │   GitLab EE     │      │ GitLab Runner   │      │     Harbor      │    │
│  │   :8929         │──────│   (Docker)      │──────│     :8880       │    │
│  │   代码仓库       │      │   CI 执行器      │      │   镜像仓库       │    │
│  └─────────────────┘      └────────┬────────┘      └─────────────────┘    │
│                                    │                                        │
│                                    │ kubectl apply                          │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                         K3s 集群                                     │  │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐        │  │
│  │  │ 前端 Pod  │  │ Gateway   │  │ 微服务 A  │  │ 微服务 B  │        │  │
│  │  └───────────┘  └───────────┘  └───────────┘  └───────────┘        │  │
│  │                                                                     │  │
│  │  Traefik Ingress (:8083) ← 业务流量入口                             │  │
│  │  CoreDNS → 转发 .renew.com 到 dnsmasq                               │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                    │                                        │
│                                    │ *.renew.com                            │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                    Docker Compose（基础设施层）                       │  │
│  │  MySQL | Redis | MongoDB | RabbitMQ | Consul | Apollo | OTel       │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 前置条件与部署顺序

> **前提**：K3s 集群已部署并正常运行（`kubectl get nodes` Ready），CoreDNS 已配置 `.renew.com` 转发。

| 阶段 | Skill/命令 | 说明 |
|------|-----------|------|
| **前提** | K3s 已部署 | `kubectl get nodes` Ready |
| **阶段一** | `setup-gitlab-runner start` | 一站式部署 CI Job 执行环境 + Runner 容器 |
| **阶段二** | `setup-gitlab-runner register` | 注册 Runner 到 GitLab（需提前获取 glrt- Token） |
| **阶段三** | `setup-gitlab-runner verify` | 验证执行环境就绪（含基础设施层检查） |
| **阶段四** | `/setup-cicd demo` | Demo 端到端验证（本 action） |

**快速部署检查清单**：

```
□ DNS 服务已部署（dnsmasq）
□ 目标机器 DNS 已指向 dnsmasq
□ 目标机器可访问 gitlab.renew.com、harbor.renew.com
□ 已从 GitLab 获取 Runner Registration Token（glrt- 格式）
□ 已准备好 Harbor admin 密码
□ Apollo tech.common 配置模板已导入
```

---

## 执行模式

本 action **分两阶段执行**，中间等待用户确认：

| 阶段 | 内容 | 触发方式 |
|------|------|---------|
| **阶段一** | 检查 CI/CD 环境就绪 + 输出完整操作清单 | 执行命令后自动运行 |
| **阶段二** | 推送 Demo 代码到 GitLab | 用户明确回复「可以」后继续 |

**固定 Git 地址**（`demo` 组，SSH 协议）：

```
后端：ssh://git@gitlab.renew.com:2222/demo/demo-backend.git
前端：ssh://git@gitlab.renew.com:2222/demo/demo-frontend.git
```

> 需在 GitLab 创建名为 `demo` 的组，并在组内创建对应项目。

---

## 步骤

### 步骤 1：环境就绪检查（阶段一）

**检查 CI/CD 工具就绪**：

```bash
SSH_CMD "ls /opt/tech-stack/cicd/app.sh /opt/tech-stack/cicd/kubectl-bin /opt/tech-stack/cicd/jq-static 2>/dev/null && echo 'CICD_OK' || echo 'CICD_MISSING'"
```

- 返回 `CICD_MISSING` → 终止，提示先执行 `/setup-gitlab-runner start`（由该 skill 统一准备 CI Job 执行环境）

**检查 GitLab Runner 在线**：

```bash
SSH_CMD "docker exec tech-gitlab-runner-nonprod gitlab-runner verify 2>/dev/null | grep -i 'alive' && echo 'RUNNER_OK' || echo 'RUNNER_OFFLINE'"
```

- 返回 `RUNNER_OFFLINE` → 提示先完成 Runner 注册（`/setup-gitlab-runner register`）

> namespace 和 harbor-registry Secret 由 app.sh 在首次 Pipeline 时自动创建（幂等），无需预先检查。

---

### 步骤 2：输出完整操作清单（阶段一末尾）

> **以下内容作为格式化文本输出给用户**，供用户对照逐项完成。

```
╔══════════════════════════════════════════════════════════════════════╗
║         CI/CD Demo 验证 — 前置操作清单（请逐项完成后确认）              ║
╚══════════════════════════════════════════════════════════════════════╝

──────────────────────────────────────────────────────────────────────
A. GitLab 准备
──────────────────────────────────────────────────────────────────────

A1. 创建 demo 组
    访问 http://gitlab.renew.com → Groups → New group
    · Group name: demo
    · Visibility Level: Private

A2. 在 demo 组下创建两个项目（均选 Private）
    · demo-backend
    · demo-frontend

> **GitLab Variables**：无需配置。
> - `HARBOR_PASSWORD`：由 `setup-gitlab-runner start` 在部署时注入到 `/opt/tech-stack/cicd/app.sh`
> - `KUBECONFIG`：由 `setup-gitlab-runner` 分发到 `/opt/tech-stack/cicd/kubeconfig`，CI Job 自动挂载

──────────────────────────────────────────────────────────────────────
B. SSH Key 配置（代码推送必须）
──────────────────────────────────────────────────────────────────────

B1. 本地生成 SSH 密钥（若已有可跳过）
    ssh-keygen -t ed25519 -C "your-email@example.com"

B2. 添加公钥到 GitLab
    GitLab → 右上角头像 → Edit profile → SSH Keys → Add new key
    粘贴 ~/.ssh/id_ed25519.pub（或 ~/.ssh/id_rsa.pub）内容

B3. 验证 SSH 连接
    ssh -T git@gitlab.renew.com -p 2222
    预期输出：Welcome to GitLab, @<username>!

──────────────────────────────────────────────────────────────────────
C. Apollo 配置
──────────────────────────────────────────────────────────────────────
访问：http://apollo.renew.com

C1. 确认 tech.common 公共 namespace 已创建并发布
    （若未创建：管理员工具 → 命名空间管理 → 创建公共 namespace
     → 文本编辑粘贴 <skill_dir>/references/apollo-tech-common.properties
     内容 → 发布）

C2. 创建 demo-backend 应用
    · 应用管理 → 创建应用 → AppId: demo-backend
    · Namespace 管理 → 关联公共 namespace → tech.common
    · 在项目 namespace 中覆盖以下配置（可复制粘贴）：

    ```properties
    # demo-backend 配置
    ops.k8sReplicas=1                       # Pod 副本数
    ops.appCpuLimit=0.5                     # CPU 限制（核）
    ops.appMemoryLimit=512                  # 内存限制（Mi）
    ops.javaVersion=21                      # JDK 版本
    ops.appDomain=demo.fat.api.renew.com    # 外部访问域名
    ops.supportOtel=true                    # 启用 OTel 链路追踪和日志采集
    ops.otelMode=bridge                     # Bridge 模式（SB 3.x 主力）
    ```

C3. 创建 demo-frontend 应用
    · 应用管理 → 创建应用 → AppId: demo-frontend
    · Namespace 管理 → 关联公共 namespace → tech.common
    · 在项目 namespace 中覆盖以下配置（可复制粘贴）：

    ```properties
    # demo-frontend 配置
    ops.k8sReplicas=1                       # Pod 副本数
    ops.appCpuLimit=0.2                     # CPU 限制（核）
    ops.appMemoryLimit=128                  # 内存限制（Mi）
    ops.nodejsVersion=20                    # Node.js 版本（仅构建时）
    ops.nodejsBuildCommand=npm install && npm run build    # 前端构建命令
    ops.htmlPackageDirectory=dist           # 构建产物目录
    ops.appDomain=demo.fat.web.renew.com    # 外部访问域名
    ```

> **配置说明**：关联 tech.common 后继承通用默认值，仅覆盖上述必要项即可。

══════════════════════════════════════════════════════════════════════
以上操作（A、B、C）全部完成后，请回复「可以」，将自动推送 Demo 代码。
══════════════════════════════════════════════════════════════════════
```

---

### 步骤 3：⏸ 等待用户确认

> **强制停止**：此处不自动继续，等待用户明确回复「可以」后才执行步骤 4。
> 若用户有疑问，耐心解答，直到用户确认所有前置操作已完成为止。

---

### 步骤 4：推送 Demo 代码（阶段二）

用户确认后，在本地执行以下命令推送 Demo 代码：

**推送前检查**（SSH 连通性）：

```bash
ssh -T git@gitlab.renew.com -p 2222 -o StrictHostKeyChecking=no
# 预期：Welcome to GitLab, @root!
```

**推送后端（demo-backend）**：

```bash
# 清理旧目录（避免重复执行冲突）
rm -rf /tmp/cicd-demo-backend

# 复制模板（排除 target/ 编译产物）
cp -r ${CLAUDE_SKILL_DIR}/references/demo-backend/ /tmp/cicd-demo-backend/
rm -rf /tmp/cicd-demo-backend/target

# 初始化并推送到 GitLab（SSH 协议，端口 2222）
cd /tmp/cicd-demo-backend
git init
git remote add origin ssh://git@gitlab.renew.com:2222/demo/demo-backend.git
git checkout -b dev
git add .
git commit -m "feat: CI/CD Demo 后端项目初始化"
git push -u origin dev
```

**推送前端（demo-frontend）**：

```bash
# 清理旧目录
rm -rf /tmp/cicd-demo-frontend

# 复制模板
cp -r ${CLAUDE_SKILL_DIR}/references/demo-frontend/ /tmp/cicd-demo-frontend/
cd /tmp/cicd-demo-frontend

# 初始化并推送
git init
git remote add origin ssh://git@gitlab.renew.com:2222/demo/demo-frontend.git
git checkout -b dev
git add .
git commit -m "feat: CI/CD Demo 前端项目初始化"
git push -u origin dev
```

> **推送失败排查**：
> - SSH 连通性：`ssh -T git@gitlab.renew.com -p 2222`（预期 `Welcome to GitLab`）
> - DNS 解析：`nslookup gitlab.renew.com`（预期解析到 infra-nginx 所在机器 IP）
> - 项目是否已创建：确认 GitLab `demo` 组下存在 `demo-backend` 和 `demo-frontend` 项目

---

### 步骤 5：SSH 自动监控 Pipeline 状态

推送成功后，**立即通过 SSH 连接到 Runner 所在机器（同 `--host` 参数机器）**，轮询监控 Pipeline 执行状态：

#### 5.1 监控 Runner 接收 Job

```python
# 使用 paramiko SSH 连接，每 15 秒读取 Runner 最新日志（过去 30 秒内）
SSH_CMD "docker logs tech-gitlab-runner-nonprod --since 30s 2>&1"
```

观察以下关键日志：

| 日志关键字 | 含义 | 处理 |
|-----------|------|------|
| `Checking for jobs... received` + `repo_url=.*/demo-backend` | 后端 Job 已接收 | 继续等待 |
| `Checking for jobs... received` + `repo_url=.*/demo-frontend` | 前端 Job 已接收 | 继续等待 |
| `Job succeeded` | Job 成功 | 通知用户点击 fat_deploy |
| `Job failed` + `duration_s < 30` | Job 快速失败（通常是配置问题）| 执行 5.2 诊断 |
| `Job failed` + `duration_s > 60` | Job 正常失败（构建错误）| 提示查看 GitLab Pipeline 日志 |

#### 5.2 快速失败诊断（duration_s < 30）

Job 在 30 秒内失败，通常是以下原因之一，按序检查：

**检查 1：Runner 能否访问 GitLab（git clone 失败）**

```bash
# 在 Runner 容器内测试
SSH_CMD "docker exec tech-gitlab-runner-nonprod curl -sI http://gitlab.renew.com/ 2>/dev/null | head -3"
```

- 返回 `302 Found` → GitLab 可访问，git clone 应无问题
- 返回 `000` 或连接拒绝 → DNS/网络问题，检查 DNS 配置

**检查 2：GitLab external_url 是否含端口**

```bash
# 在 GitLab 所在机器检查
SSH_CMD "docker exec tech-gitlab grep external_url /etc/gitlab/gitlab.rb"
```

- 正确：`external_url 'http://gitlab.renew.com'`（无端口）
- 错误：`external_url 'http://gitlab.renew.com:8929'` → 执行修复

**检查 3：`before_script` 中 JAVA_HOME 路径是否正确**

`maven:3.9-eclipse-temurin-21` 镜像内 JDK 已由镜像配置好，`.gitlab-ci.yml` 不应手动覆盖 `JAVA_HOME`。

#### 5.3 等待构建完成

- **`jar` stage（Maven 构建）**：首次约 5-10 分钟（需下载依赖），后续有缓存约 2-3 分钟
- **`build` stage（前端构建）**：约 1-2 分钟

构建完成后，通知用户：

```
✅ Pipeline build/jar stage 已完成！

现在请在 GitLab 手动触发 fat_deploy：

━━━━ demo-backend（后端）━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
访问：http://gitlab.renew.com/demo/demo-backend/-/pipelines
  → 找到最新 Pipeline → 点击 fat_deploy job → 点击右侧播放按钮

━━━━ demo-frontend（前端）━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
访问：http://gitlab.renew.com/demo/demo-frontend/-/pipelines
  → 找到最新 Pipeline → 点击 fat_deploy job → 点击右侧播放按钮

fat_deploy 触发后告知我，将自动检查部署结果。
```

---

### 步骤 6：验证部署结果

用户告知 fat_deploy 已触发后，通过 SSH 轮询 K3s 资源（约 1-3 分钟）：

**完整验证命令**：

```bash
# Pod 状态
SSH_CMD "kubectl get deployment,pods -n fat"

# HPA / PDB（后端副本数控制）
SSH_CMD "kubectl get hpa,pdb -n fat"

# Ingress（路由规则）
SSH_CMD "kubectl get ingress -n fat"

# 端点访问验证
SSH_CMD "curl -s http://demo.fat.api.renew.com/actuator/health"
SSH_CMD "curl -s http://demo.fat.web.renew.com | head -5"
```

预期结果：
- Pods 状态 `Running`
- Ingress 已创建（`demo.fat.api.renew.com`、`demo.fat.web.renew.com`）
- 后端：`{"status":"UP"}`
- 前端：返回 HTML 页面内容

---

## 验证清单

- [ ] GitLab `demo` 组已创建（Private）
- [ ] `demo-backend`、`demo-frontend` 项目已在 `demo` 组下创建（Private）
- [ ] app.sh 已上传到 /opt/tech-stack/cicd/（HARBOR_PASSWORD 已由 setup-gitlab-runner 注入，KUBECONFIG 已挂载）
- [ ] SSH Key 已添加到 GitLab（`ssh -T git@gitlab.renew.com -p 2222` 返回 Welcome）
- [ ] Apollo `tech.common` namespace 已创建并发布
- [ ] Apollo `demo-backend` 应用配置已发布（关联 tech.common）
- [ ] Apollo `demo-frontend` 应用配置已发布（关联 tech.common）
- [ ] Demo 代码已推送（两个项目均有 dev 分支）
- [ ] Pipeline jar/build stage 自动完成（绿色 ✅）
- [ ] fat_deploy 手动触发并成功（绿色 ✅）
- [ ] K3s Pod 运行正常（`kubectl get pods -n fat`）
- [ ] `curl http://demo.fat.api.renew.com/actuator/health` 返回 `{"status":"UP"}`
- [ ] `curl http://demo.fat.web.renew.com` 返回前端页面

---

## 故障排查

### K3s 相关

| 问题 | 症状 | 解决方案 |
|------|------|---------|
| Pod ContainerCreating | 镜像拉取失败 | 检查 registries.yaml |
| Traefik bind denied | 容器端口 < 1024 | 容器内端口改为 8000 |
| DNS 解析失败 | nslookup 失败 | 检查 CoreDNS 转发配置 |

### GitLab Runner 相关

| 问题 | 症状 | 解决方案 |
|------|------|---------|
| GitLab 不可达 | register 失败 | 检查 DNS 配置 |
| Docker permission denied | docker build 失败 | `chmod 666 /var/run/docker.sock` |
| 镜像拉取超时 | CI 作业卡住 | 配置 Docker 镜像加速器 |
| kubectl/jq 找不到 | app.sh 报错 | 检查 Runner volumes 是否挂载静态工具，必要时重跑 `/setup-gitlab-runner start` |

### CI/CD 相关

| 问题 | 症状 | 解决方案 |
|------|------|---------|
| Harbor 密钥缺失 | ImagePullBackOff | 重跑 `/setup-gitlab-runner start`（会重建 harbor-registry Secret） |
| Apollo 配置缺失 | app.sh 报错 | 在 Apollo 创建 tech.common 并导入模板 |
| 基础镜像不存在 | 构建失败 | 重跑 `/setup-gitlab-runner start`（会推送基础镜像到 Harbor） |

---

## 常用命令速查

```bash
# ========== K3s ==========
kubectl get nodes -o wide
kubectl get pods -A
systemctl status k3s
systemctl restart k3s

# ========== GitLab Runner ==========
docker ps --filter name=gitlab-runner
docker logs -f tech-gitlab-runner
docker exec tech-gitlab-runner-nonprod gitlab-runner list

# ========== CI/CD ==========
# 部署应用到 K3s（在 Runner 机器执行）
/opt/tech-stack/cicd/app.sh

kubectl get deployment -n fat
kubectl logs -f deployment/<app-id> -n fat
kubectl exec -it <pod> -n fat -- sh
```

---

## 配置文件位置（目标机器）

| 组件 | 路径 |
|------|------|
| K3s kubeconfig | `/etc/rancher/k3s/k3s.yaml` |
| K3s 镜像加速 | `/etc/rancher/k3s/registries.yaml` |
| Runner 配置 | `/opt/tech-stack/gitlab-runner/` |
| CI Job 脚本 | `/opt/tech-stack/cicd/app.sh` |
| CI Job kubeconfig | `/opt/tech-stack/cicd/kubeconfig` |
| CI Job Maven 配置 | `/opt/tech-stack/cicd/settings.xml` |
| 静态工具 | `/opt/tech-stack/cicd/kubectl-bin`、`jq-static`、`docker-static` |
