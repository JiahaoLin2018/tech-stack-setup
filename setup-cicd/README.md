# setup-cicd — 业务接入 CI/CD 指导

面向业务项目的 CI/CD 接入指南：在已就绪的执行环境（由 setup-gitlab-runner 提供）之上，把 Java / 前端 / Python 项目接入 `git push → Harbor → K3s` 完整 Pipeline。

## 概述

```
git push → GitLab Pipeline → app.sh → Docker build → Harbor → kubectl apply → K3s Pod
                                 ↑
                          从 Apollo 读取配置
                      （副本数/CPU/内存/域名/版本）
```

**核心理念**：开发者只需在 Apollo 配置 `ops.*` 项目参数，添加 `.gitlab-ci.yml` 后推送代码，剩余全部由 app.sh 自动完成（生成 Deployment、Service、Ingress、HPA、PDB）。

## 前置条件

| 依赖 | 说明 |
|------|------|
| K3s 集群 | `kubectl get nodes` Ready |
| GitLab EE | 可通过 `gitlab.renew.com` 访问 |
| **CI/CD 执行环境** | 由 `setup-gitlab-runner start` + `register` + `verify` 部署就绪（含 app.sh / kubeconfig / 静态工具 / Harbor 基础镜像 / Harbor Secret） |
| Apollo | `tech.common` namespace 已导入配置模板（位于 `<skill_dir>/references/apollo-tech-common.properties`） |

## 快速开始

> Demo 验证详情见 [`actions/demo.md`](actions/demo.md)，正式项目接入见 [`actions/integrate.md`](actions/integrate.md)。

```bash
# 前置：CI/CD 执行环境必须先部署（见 setup-gitlab-runner）
# /setup-gitlab-runner start --host <RUNNER_HOST>
# /setup-gitlab-runner register --host <RUNNER_HOST>
# /setup-gitlab-runner verify --host <RUNNER_HOST>

# 1. Demo 端到端验证（首次必做，验证链路通畅）
/setup-cicd demo --host <RUNNER_HOST>

# 2. 正式项目接入
/setup-cicd integrate
```

## GitLab CI/CD Variables

> `HARBOR_PASSWORD` 由 `setup-gitlab-runner start` 在部署时注入到 `app.sh`，`KUBECONFIG` 由 Runner 自动挂载，无需 GitLab 变量配置。
> 钉钉通知在各项目 `.gitlab-ci.yml` 的 `variables` 中按需开启（已提供注释模板）。

| Variable | 说明 | 配置方式 |
|----------|------|---------|
| `DINGTALK_WEBHOOK` | 钉钉通知 Webhook（可选） | 项目 `.gitlab-ci.yml` variables 取消注释 |

## Apollo 配置项完整说明

> 以下配置项已在 `tech.common` 中预设默认值，项目只需覆盖有特殊需求的项。

### 通用配置（所有项目类型）

| 配置项 | 默认值 | 说明 | 约束 |
|--------|--------|------|------|
| `ops.k8sReplicas` | `1` | 常态副本数 | 必须为正整数 |
| `ops.k8sReplicasMin` | 空 | HPA 最小副本 | 与 Max 同时配置才启用 HPA |
| `ops.k8sReplicasMax` | 空 | HPA 最大副本 | 与 Min 同时配置才启用 HPA |
| `ops.k8sTargetCPU` | `70` | HPA CPU 触发阈值(%) | 50-90 |
| `ops.k8sTargetMemory` | `80` | HPA 内存触发阈值(%) | 60-95 |
| `ops.k8sPdbMinAvailable` | `1`（多副本自动） | PDB 最小可用副本 | **⚠️ 必须 < replicas**；设 0 禁用 PDB |
| `ops.k8sUpdateStrategy` | `RollingUpdate` | 更新策略 | `RollingUpdate` / `Recreate` |
| `ops.appCpuLimit` | `1` | CPU 限制（核） | **⚠️ 最低 0.2**（requests 硬编码 100m） |
| `ops.appMemoryLimit` | `1024` | 内存限制（Mi） | **⚠️ Python 最低 256**（requests 硬编码 256Mi） |
| `ops.appDomain` | 空 | 域名，多个用空格分隔 | 不配置则不创建 Ingress，Service 始终创建 |
| `ops.appDomainReverseProxyUri` | `/` | 反向代理路径 | 子目录部署时填 `/app` 等 |
| `ops.persistentStorage` | `false` | 是否启用持久化存储 | `true` / `false` |
| `ops.persistentStorageSize` | `1` | 存储大小（Gi） | - |
| `ops.persistentStoragePath` | `/data` | 存储挂载路径 | - |

### Java 项目配置

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `ops.javaVersion` | `21` | JDK 版本：`8` / `11` / `17` / `21` |
| `ops.mavenBuildCommand` | `mvn clean install -Dmaven.test.skip=true` | Maven 构建命令 |
| `ops.javaCmdOptions` | `-server -Dlog.dir=/app/logs/app -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp` | JVM 参数（**⚠️ 不要设置 -Xmx/-Xms**，脚本自动计算） |
| `ops.appHealthUri` | `/actuator/health` | 健康检查路径 |
| `ops.appPort` | 空 | 应用端口（不填则读取 server.port） |
| `ops.autoReuseImage` | `true` | 复用已有镜像（开发 `true`，生产 `false`） |
| `ops.supportOtel` | `true` | 是否启用 OTel 链路追踪和日志采集 |
| `ops.otelMode` | `bridge` | OTel 模式：`bridge`（SB 3.x 主力，Micrometer + OTel Bridge）/ `agent`（SB 2.x 兜底，Java Agent） |

### 前端项目配置

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `ops.nodejsVersion` | `20` | 构建阶段 Node.js 版本（仅构建用，运行时固定 nginx:1.27） |
| `ops.nodejsBuildCommand` | `npm install && npm run build` | 构建命令 |
| `ops.htmlPackageDirectory` | `dist` | 打包产物目录（Vite: `dist`，Webpack: `build`） |

### Python 项目配置

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `ops.pythonVersion` | `3.11` | Python 版本：`3.9` / `3.10` / `3.11` / `3.12` |
| `ops.pyBuildCommand` | `pip install -r requirements.txt` | 构建命令 |
| `ops.pyStartCommand` | `python main.py` | 启动命令（**⚠️ 不能含双引号**） |
| `ops.appPort` | 空 | **必须配置**（Python 不自动检测端口） |
| `ops.appHealthUri` | `/actuator/health` | 建议改为 `/health` |
| `ops.autoReuseImage` | `true` | 建议改为 `false` |

## Apollo 配置优先级与覆盖机制

```
tech.common（公共 namespace）
├── 通用默认值：k8sReplicas=1, appCpuLimit=1, appMemoryLimit=1024 ...
└── 语言默认值：javaVersion=21, nodejsVersion=20, pythonVersion=3.11 ...

    ↓ 项目关联后继承，仅覆盖需要定制的项

my-app（项目 namespace）
└── 覆盖项示例：appDomain=order.fat.api.renew.com, appMemoryLimit=2048
```

**零配置启动**：项目关联 `tech.common` 后，无需额外配置即可完成最小部署，只需覆盖 `ops.appDomain` 使外部可访问。

## 部署示例

### 单副本（开发/Demo）

```properties
ops.k8sReplicas = 1
# → Deployment，无 HPA，无 PDB
```

### 固定多副本（推荐生产）

```properties
ops.k8sReplicas = 2
# → Deployment(2) + PDB(minAvailable=1)，PDB 自动创建，无需额外配置
```

### 自动扩缩容（高流量服务）

```properties
ops.k8sReplicas = 2
ops.k8sReplicasMin = 2
ops.k8sReplicasMax = 10
ops.k8sTargetCPU = 70
# → Deployment + HPA(2-10) + PDB(minAvailable=1，自动创建)
```

### 显式禁用 PDB（特殊场景）

```properties
ops.k8sReplicas = 2
ops.k8sPdbMinAvailable = 0
# → Deployment(2)，无 PDB
```

## 多语言配置示例

### Java（Spring Boot 3.5 + JDK 21）

```properties
# 在项目 namespace 中覆盖
ops.k8sReplicas = 2
ops.appCpuLimit = 1
ops.appMemoryLimit = 2048
ops.appDomain = order.fat.api.renew.com
ops.javaVersion = 21
ops.supportOtel = true      # 启用链路追踪和日志采集
ops.otelMode = bridge       # bridge（SB 3.x 主力）/ agent（SB 2.x 兜底）
```

`.gitlab-ci.yml` 只需修改 `APP_ID`，复制 `references/.gitlab-ci.yml` 使用。

### Java（老项目 JDK 11）

```properties
ops.k8sReplicas = 1
ops.appCpuLimit = 0.5
ops.appMemoryLimit = 512
ops.appDomain = legacy.fat.api.renew.com
ops.javaVersion = 11
ops.supportOtel = true      # 启用链路追踪和日志采集
ops.otelMode = agent        # JDK <17 自动强制切换为 agent 模式
```

> Harbor 中需有 `jdk:11` 基础镜像（由 `setup-gitlab-runner start` 推送）。

### 前端（Vue 3 + Node 20）

```properties
ops.k8sReplicas = 1
ops.appCpuLimit = 0.2
ops.appMemoryLimit = 128
ops.appDomain = demo.fat.web.renew.com
ops.nodejsVersion = 20
ops.nodejsBuildCommand = npm install && npm run build
ops.htmlPackageDirectory = dist
```

`.gitlab-ci.yml` 复制 `references/demo-frontend/.gitlab-ci.yml` 并修改 `APP_ID`。

### Python（FastAPI + 自动扩容）

```properties
ops.k8sReplicas = 2
ops.k8sReplicasMin = 2
ops.k8sReplicasMax = 8
ops.k8sTargetCPU = 60
ops.appCpuLimit = 1
ops.appMemoryLimit = 512
ops.appDomain = ai.fat.api.renew.com
ops.pythonVersion = 3.11
ops.pyBuildCommand = pip install -r requirements.txt
ops.pyStartCommand = uvicorn main:app --host 0.0.0.0 --port 8000
ops.appPort = 8000
ops.appHealthUri = /health
ops.autoReuseImage = false
```

## CI/CD Pipeline 设计

### 前后端差异

| 对比项 | 后端（Java） | 前端（Node.js） |
|--------|-------------|----------------|
| 构建 stage | `jar`（Maven 编译 → `target/*.jar`） | `build`（npm build → `dist/`） |
| 产物缓存 | GitLab Cache | GitLab Cache |
| 运行时基础镜像 | `harbor.renew.com/library/jdk:{version}` | `harbor.renew.com/library/nginx:1.27` |
| HPA/PDB | 支持 | 通常不需要 |
| 健康检查 | `/actuator/health` | `/`（根路径） |

### 设计原则

| 原则 | 说明 |
|------|------|
| 先构建后部署 | jar/build stage 独立，产物通过 Cache 传递给 deploy stage |
| 手动触发部署 | 所有 deploy job 需手动确认，防止误操作 |
| 环境隔离 | dev 分支 → sit/fat/uat，tag → prod |
| 生产独立构建 | prod_jar/prod_build 使用独立 cache key 和 prod tag Runner |
| YAML anchor | `<<: *template` 减少重复代码 |

## Harbor 镜像拉取密钥

`harbor-registry` 是 K8s `docker-registry` 类型 Secret，Kubelet 拉取私有镜像时自动使用。

**`setup-gitlab-runner start` 在 `fat` namespace 预创建此 Secret，其他 namespace 由 app.sh 在首次 Pipeline 时自动创建（幂等）。**

```bash
# 手动创建（排障用）
kubectl create secret docker-registry harbor-registry \
  --docker-server=harbor.renew.com \
  --docker-username=admin \
  --docker-password=<HARBOR_PASSWORD> \
  -n fat --dry-run=client -o yaml | kubectl apply -f -
```

**生产环境建议**：使用 Harbor Robot Account（只读权限）替代 admin 密码。

## 版本兼容与扩展

当前支持版本：

| 语言 | 支持版本 | 基础镜像 |
|------|---------|---------|
| Java | 8, 11, 17, 21 | `harbor.renew.com/library/jdk:{version}` |
| 前端 | Node 16, 18, 20（构建），nginx 1.27（运行） | `harbor.renew.com/library/nginx:1.27` |
| Python | 3.9, 3.10, 3.11, 3.12 | `harbor.renew.com/library/python:{version}` |

**新增语言版本步骤**（以 JDK 25 为例）：
1. 修改 `~/.claude/skills/setup-gitlab-runner/references/app.sh` 的 `getJavaEnv()` 函数，添加 `"25")` case
2. 修改 `~/.claude/skills/setup-gitlab-runner/actions/start.md`，在推送基础镜像步骤添加 JDK 25 的 pull/tag/push 命令
3. 手动在 Runner 机器推送新镜像到 Harbor

## 常见问题

| 现象 | 原因 | 解决 |
|------|------|------|
| `无法从 Apollo 获取配置` | AppId 不存在或 tech.common 未关联 | Apollo Portal 创建 AppId 并关联 namespace |
| `Pod 无法创建（limits < requests）` | `appMemoryLimit < 256`（Python）或 `appCpuLimit < 0.2` | 调高配置值 |
| `ImagePullBackOff` | Harbor 密钥未创建或密码错误 | 检查 `kubectl get secret harbor-registry -n fat` |
| `Ingress 不可达` | Traefik 未配置或 DNS 未解析到 Traefik IP | 检查 `kubectl get ingress -n fat` 和 dnsmasq 配置 |
| `HPA 不生效` | `k8sReplicasMin` / `k8sReplicasMax` 未同时配置 | 确认两项均已在 Apollo 配置并发布 |
| `PDB 阻塞 drain` | `k8sPdbMinAvailable >= k8sReplicas` | 降低 PDB 值或升高副本数 |
| `kubectl/jq 找不到` | Runner volumes 未挂载宿主机工具目录 | 检查 Runner config.toml volumes 配置 |
| `Apollo curl 超时挂起` | Apollo 短暂不可达 | 检查 Apollo 服务状态和 DNS 解析 |

## 扩展阅读

| 文档 | 用途 |
|------|------|
| [app.sh 部署规范](../setup-gitlab-runner/references/app-sh-spec.md) | CI Job 部署脚本生成的 K8s 资源结构说明 |
| Apollo 配置模板 | `<skill_dir>/references/apollo-tech-common.properties`（首次部署导入 Apollo） |
| Pipeline 模板 | `references/.gitlab-ci.yml`（单体项目）、`references/.gitlab-ci-aggregated.yml`（聚合项目） |
