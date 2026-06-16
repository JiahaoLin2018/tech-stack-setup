# Task 22 — CI/CD Pipeline 验证（Demo 项目）

- **状态**: ⬜ 待执行
- **目标机器**: GitLab(97) + K3s/Runner(93) + Apollo(93)
- **Skill**: setup-cicd、setup-gitlab-runner
- **前置依赖**: Task 20 (K3s), Task 21 (DMZ Traefik), GitLab 可访问, Harbor 可访问, Apollo 可访问

## 目标

通过 Demo 项目验证完整的 CI/CD 自动化发布流程：
**git push → GitLab Pipeline → Apollo 读配置 → Docker 构建 → Harbor 推送 → K3s 部署 → 域名访问**

---

## 执行流程

> **顺序关键**：Apollo tech.common → CI/CD 环境 → Runner 启动 → Runner 注册 → GitLab 配置 → 推代码验证
> `setup-cicd start` 必须在 `setup-gitlab-runner start` 之前执行，确保 Runner 容器挂载目录已有内容。

---

### 阶段 A：准备 Apollo 公共 namespace（首次必做）

> **所有项目部署的全局前提**：app.sh 从 Apollo `tech.common` namespace 读取 `ops.*` 配置项，namespace 不存在时直接报错退出。

**操作步骤**（Apollo Portal 手动操作）：

1. 访问 `http://apollo.renew.com:8070` → 管理员工具 → **命名空间管理**
2. 创建公共 namespace：名称填 `tech.common`，类型选**公共**
3. 进入 `tech.common` → 文本编辑 → 将 `<skill_dir>/references/apollo-tech-common.properties` 内容粘贴进去 → **发布**

> 此步骤只需做一次，后续所有项目只需关联该 namespace 即可。

**验证**：在 Apollo Portal 确认 `tech.common` namespace 存在且已发布。

---

### 阶段 B：部署 CI/CD 基础环境

> 安装宿主机工具 + 上传 app.sh + 配置 kubeconfig + 推送基础镜像

```bash
/setup-cicd start --host 192.168.82.93 --user root --password foxconn.88
```

**此步骤完成**：
- 静态工具下载到 `/opt/tech-stack/cicd/`（CI Job 通过 volumes 挂载使用）：`kubectl-bin`、`jq-static`、`docker-static`
- `/opt/tech-stack/cicd/app.sh` — CI/CD 部署脚本（已设置可执行权限）
- `/opt/tech-stack/cicd/settings.xml` — Maven 配置（Nexus 私服镜像）
- `/opt/tech-stack/cicd/kubeconfig` — K3s 连接凭据（server 地址已改为 192.168.82.93）
- Harbor 基础镜像已推送：`jdk:8/11/17/21`、`nginx:1.27`、`python:3.9/3.10/3.11/3.12`
- K3s `fat` namespace 已创建 + Harbor 镜像拉取密钥已配置

---

### 阶段 B.1：验证 CI/CD 基础环境

```bash
/setup-cicd verify --host 192.168.82.93 --user root --password foxconn.88
```

确认输出均为 ✅：app.sh 存在、kubeconfig 可用、kubectl/jq/docker 可调用、Harbor 可达、Runner 已挂载。

---

### 阶段 C：启动 GitLab Runner

> 此时 `/opt/tech-stack/cicd/` 目录已有 app.sh、settings.xml 和 kubeconfig，Runner 容器挂载后直接可用。

```bash
/setup-gitlab-runner start --host 192.168.82.93 --user root --password foxconn.88
```

**此步骤完成**：Runner 容器 `tech-gitlab-runner` 启动，挂载 `/opt/tech-stack/cicd/` 目录。

**CI Job 挂载清单**：
| 宿主机路径 | 容器内路径 | 用途 |
|-----------|-----------|------|
| `/opt/tech-stack/cicd/app.sh` | `/opt/tech-stack/cicd/app.sh` | 部署脚本 |
| `/opt/tech-stack/cicd/settings.xml` | `/root/.m2/settings.xml` | Maven 配置（Nexus 镜像） |
| `/opt/tech-stack/cicd/kubeconfig` | `/opt/tech-stack/cicd/kubeconfig` | K3s 凭证 |
| `/opt/tech-stack/cicd/kubectl-bin` | `/usr/local/bin/kubectl` | 静态 kubectl |
| `/opt/tech-stack/cicd/jq-static` | `/usr/local/bin/jq` | 静态 jq |
| `/opt/tech-stack/cicd/docker-static` | `/usr/local/bin/docker` | docker CLI（构建/推送镜像） |
| `/var/run/docker.sock` | `/var/run/docker.sock` | Docker daemon socket |

---

### 阶段 D：注册 Runner 到 GitLab

**前置操作**（GitLab UI，需先于执行命令完成）：

1. 访问 `http://gitlab.renew.com` → Admin Area → Overview → Runners → **New instance runner**
   （或在 Group → Settings → CI/CD → Runners → New Group Runner）
2. Platform 选 Linux，点击创建
3. 复制生成的 Token（`glrt-` 格式）

**执行注册**：

```bash
/setup-gitlab-runner register --host 192.168.82.93 --user root --password foxconn.88
```

提示输入 Token 时粘贴上一步复制的 `glrt-` Token。

**注册完成后在 GitLab UI 确认**：

| 配置项 | 建议值 |
|--------|--------|
| Run untagged jobs | ✅ 启用 |
| Protected | ❌ 不启用 |

**验证**：Runner 列表出现绿色圆点（在线状态）。

---

### 阶段 E：GitLab 准备（手动）

#### E1. 创建 demo 组

访问 `http://gitlab.renew.com` → Groups → New group：
- Group name: `demo`，Visibility: Private

#### E2. 在 demo 组下创建两个项目（均为 Private）

- `demo-backend`
- `demo-frontend`

#### E3. 配置 SSH Key（代码推送必须）

本地生成 SSH 密钥（若已有可跳过）：
```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
```

添加公钥到 GitLab：右上角头像 → Edit profile → SSH Keys → Add new key（粘贴 `~/.ssh/id_ed25519.pub`）

验证连接：
```bash
ssh -T git@gitlab.renew.com -p 2222
# 预期：Welcome to GitLab, @<username>!
```

---

### 阶段 F：Apollo 应用配置（手动）

> 访问 `http://apollo.renew.com:8070`，为每个 Demo 应用创建 AppId 并关联公共 namespace。

#### F1. demo-backend

1. **应用管理 → 创建应用**：AppId = `demo-backend`
2. **Namespace 管理 → 关联公共 namespace** → 选择 `tech.common`
3. **在项目自己的 namespace 中覆盖**以下配置（仅 demo-backend 生效）：

| Key | Value | 说明 |
|-----|-------|------|
| `ops.k8sReplicas` | `1` | 常态副本数 |
| `ops.appCpuLimit` | `0.5` | CPU 限制(核) |
| `ops.appMemoryLimit` | `512` | 内存限制(Mi) |
| `ops.javaVersion` | `21` | JDK 版本 |
| `ops.appDomain` | `demo.fat.api.renew.com` | 域名 |
| `ops.supportOtel` | `false` | Demo 关闭链路追踪 |

> **端口说明**：`ops.appPort` 未配置时，app.sh 自动从 Apollo `application` namespace 的 `server.port` 读取。如未配置 application namespace，可在项目 namespace 中补充 `ops.appPort=8080`。

4. **发布**配置

#### F2. demo-frontend

1. **应用管理 → 创建应用**：AppId = `demo-frontend`
2. **Namespace 管理 → 关联公共 namespace** → 选择 `tech.common`
3. **在项目自己的 namespace 中覆盖**以下配置：

| Key | Value | 说明 |
|-----|-------|------|
| `ops.k8sReplicas` | `1` | 常态副本数 |
| `ops.appCpuLimit` | `0.2` | CPU 限制(核) |
| `ops.appMemoryLimit` | `128` | 内存限制(Mi) |
| `ops.nodejsVersion` | `20` | Node.js 版本 |
| `ops.nodejsBuildCommand` | `npm install && npm run build` | 构建命令 |
| `ops.htmlPackageDirectory` | `dist` | 打包目录 |
| `ops.appDomain` | `demo.fat.web.renew.com` | 域名 |

4. **发布**配置

---

### 阶段 G：推送 Demo 代码并触发 Pipeline

```bash
/setup-cicd demo --host 192.168.82.93 --user root --password foxconn.88
```

执行后 skill **自动分两阶段运行**：

**第一步（自动）**：检查 CI/CD 环境就绪 + 输出完整操作清单（含 GitLab 组/项目/变量、SSH Key、Apollo 配置），等待确认。
- 若阶段 E（GitLab 准备）和阶段 F（Apollo 配置）已按清单完成，直接回复「可以」。

**第二步（确认后自动）**：skill 自动推送代码到固定地址：
- `ssh://git@gitlab.renew.com:2222/demo/demo-backend.git`（dev 分支）
- `ssh://git@gitlab.renew.com:2222/demo/demo-frontend.git`（dev 分支）

**第三步（skill 自动 SSH 监控）**：推送后自动通过 SSH 监控 Runner 日志，实时反馈 Pipeline 状态：

| 状态 | skill 行为 |
|------|-----------|
| Job 被接收（`Checking for jobs... received`）| 提示构建中，继续等待 |
| `Job failed` + 耗时 < 30s | 自动诊断：检查 GitLab 可达性、`external_url` 是否含端口 |
| `Job succeeded`（jar/build stage）| 通知用户进入 GitLab 手动触发 fat_deploy |

**第四步（用户手动）**：Pipeline 构建完成后进入 GitLab 手动触发部署：
- `http://gitlab.renew.com/demo/demo-backend/-/pipelines` → 等待 `jar` stage ✅ → 手动触发 **fat_deploy**
- `http://gitlab.renew.com/demo/demo-frontend/-/pipelines` → 等待 `build` stage ✅ → 手动触发 **fat_deploy**

**fat_deploy 触发后**：skill 自动 SSH 轮询 K3s Pod 状态，Pod Running 后输出最终验证结果。

---

### 阶段 H：验证部署结果

#### H1. 使用 verify action 验证应用部署

```bash
/setup-cicd verify --host 192.168.82.93 --user root --password foxconn.88 --app-id demo-backend
/setup-cicd verify --host 192.168.82.93 --user root --password foxconn.88 --app-id demo-frontend
```

#### H2. 手动核查 K3s 资源

```bash
# 在 93 机器执行（或通过 SSH）

# --- 后端验证 ---
kubectl get deployment,pods,hpa,pdb -n fat -l app=demo-backend
kubectl get ingress -n fat

# --- 前端验证 ---
kubectl get deployment,pods -n fat -l app=demo-frontend

# --- 域名访问验证 ---
# 内网访问（通过 dnsmasq → infra-nginx → Traefik）
curl http://demo.fat.api.renew.com/actuator/health
curl http://demo.fat.web.renew.com
```

---

## CI/CD 完整链路

```
开发者推送代码 (git push origin dev)
    │
    ▼
GitLab 触发 Pipeline
    │
    ▼
Runner 启动 CI 作业容器
    ├─ 挂载 /var/run/docker.sock（构建镜像用）
    ├─ 挂载 /opt/tech-stack/cicd/（app.sh + kubeconfig + settings.xml）
    ├─ 挂载 settings.xml → /root/.m2/settings.xml（Maven Nexus 镜像）
    │
    ▼
app.sh 执行
    ├─ 1. 检测项目类型（pom.xml=java, package.json=html）
    ├─ 2. 从 Apollo 读取 tech.common 配置（副本数/CPU/内存/域名...）
    ├─ 3. Maven 构建（通过 settings.xml 从 Nexus 拉取依赖，加速下载）
    ├─ 4. Docker build → push 到 Harbor
    ├─ 5. kubectl apply → K3s 部署
    │     ├─ Deployment（副本数、资源限制、健康检查）
    │     ├─ HPA（如配置了 min/max replicas）
    │     ├─ PDB（如配置了 minAvailable）
    │     ├─ Service（ClusterIP）
    │     └─ Ingress（域名路由）
    └─ 6. rollout status 等待完成
    │
    ▼
流量链路
    ├─ 内网: dnsmasq → infra-nginx :80 → K3s Traefik :8083 → Pod
    └─ 公网: 97 Traefik :80 → K3s Traefik :8083 → Pod
```

---

## 验证清单

- [ ] K3s 节点 Ready（`kubectl get nodes`）
- [ ] Apollo `tech.common` namespace 已创建并发布
- [ ] CI/CD 基础环境已部署（`/setup-cicd verify` 全部 ✅）
- [ ] 静态工具已就绪（`kubectl-bin`、`jq-static`、`docker-static` 在 `/opt/tech-stack/cicd/`）
- [ ] settings.xml 已上传（Maven Nexus 镜像配置）
- [ ] Harbor 基础镜像已推送（`harbor.renew.com/library/jdk:21`、`nginx:1.27`）
- [ ] GitLab Runner 已启动（`docker ps --filter name=gitlab-runner`）
- [ ] GitLab Runner 已注册（GitLab UI 显示绿色圆点）
- [ ] app.sh 已上传（HARBOR_PASSWORD / KUBECONFIG 已硬编码）
- [ ] GitLab 项目已创建（demo-backend / demo-frontend）
- [ ] Apollo 应用配置已发布（demo-backend / demo-frontend 各自关联 tech.common）
- [ ] Pipeline 执行成功（GitLab → CI/CD → Pipelines，fat_deploy 绿色）
- [ ] 镜像已推送到 Harbor（`harbor.renew.com/library/demo-backend`）
- [ ] Deployment Running（`kubectl get pods -n fat`）
- [ ] HPA / PDB 已创建（后端）
- [ ] Service / Ingress 已创建
- [ ] **后端域名访问正常**：`curl http://demo.fat.api.renew.com/actuator/health`
- [ ] **前端域名访问正常**：`curl http://demo.fat.web.renew.com`

---

## 完成记录

- 开始时间:
- 完成时间:
- Pipeline URL:
- 镜像 Tag:
- 备注:
