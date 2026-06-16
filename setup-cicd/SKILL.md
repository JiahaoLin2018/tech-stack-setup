---
name: setup-cicd
description: 为业务项目提供 CI/CD 接入指导（Demo 端到端验证 + 正式项目 Apollo/.gitlab-ci.yml 接入 3 步流程）。当开发者已准备好 CI/CD 执行环境（由 setup-gitlab-runner 提供），需要把业务项目接入 Pipeline 时触发此 skill。
argument-hint: "[demo|integrate] [--host <ip>] [--app-id <appId>]"
disable-model-invocation: true
---

> **路径约定**：本文档中 `<skill_dir>` 指 SKILL.md 所在目录（安装后为 `~/.claude/skills/setup-cicd`）。

# setup-cicd — 业务接入 CI/CD 指导

负责把业务项目接入已就绪的 CI/CD 执行环境：① Demo 端到端验证；② 正式项目 Apollo 配置 + `.gitlab-ci.yml` 3 步接入。

**前置条件**：CI/CD 执行环境已由 `setup-gitlab-runner start` + `register` + `verify` 部署就绪（含 app.sh / kubeconfig / 静态工具 / Harbor Secret / 基础镜像）。

## 文档职责

| 文档 | 读者 | 内容 |
|------|------|------|
| **SKILL.md**（本文） | Claude Code（AI） | Action 路由、Apollo 配置机制、GitLab CI 模板 |
| **README.md** | 开发者 | 完整 `ops.*` 配置参考、多语言接入示例、FAQ |
| **actions/demo.md** | AI 执行 | CI/CD 端到端验证流程（架构图、部署顺序、故障排查） |
| **actions/integrate.md** | AI 执行 | 正式项目接入流程（基础设施依赖、application.yml 示例） |

## 用法

```
/setup-cicd [action] [选项]

action: demo | integrate

选项:
  --host <ip>        部署目标 IP（默认: localhost）
  --user <user>      SSH 用户名（默认: root）
  --password <pass>  SSH 密码（与 --key 二选一）
  --key <path>       SSH 私钥路径（与 --password 二选一）
  --ssh-port <n>     SSH 端口（默认: 22）
  --app-id <id>      应用 ID（integrate 时使用）
  # 注意：setup-cicd 为 E 类契约（蓝图附录 B.2），不接受 --env 参数
  # 部署环境由 Pipeline 内部 app.sh --env <dev|sit|fat|uat|prod> 决定（按 CI_COMMIT_REF 触发）
```

## Actions

| Action | 职责 | 触发时机 |
|--------|------|---------|
| `demo` | **两阶段执行**：① 检查环境 + 输出完整操作清单（GitLab `demo` 组/项目/变量、SSH Key、Apollo 配置），等待用户确认；② 用户回复「可以」后自动推送代码到固定 SSH 地址（`demo/demo-backend`、`demo/demo-frontend`），引导 fat_deploy 验证 | 首次验证 CI/CD 端到端链路 |
| `integrate` | 输出正式项目接入 3 步指南：Apollo 配置 → 添加必要文件 → 推送触发 | 新业务项目接入 CI/CD |

## 执行流程

1. 解析参数：提取 ACTION（`demo` 或 `integrate`）、HOST、SSH_USER、SSH_PORT、AUTH（password 或 key）、APP_ID
   若用户传入 `--env`：告知用户"setup-cicd 不接受 --env，部署环境由 Pipeline 内部 app.sh 自动决定"，继续执行
2. 读取 `<skill_dir>/actions/<action>.md` 按步骤执行

## 架构

```
Apollo（tech.common namespace）
    │ 读取 ops.* 配置（副本数/CPU/内存/域名/JDK版本…）
    ▼
GitLab Pipeline（.gitlab-ci.yml）
    ├── jar/build stage：Maven/npm 构建 → 产物缓存
    └── fat_deploy（手动触发）
           │
           ▼
        app.sh（由 setup-gitlab-runner 挂载到 CI Job /opt/tech-stack/cicd/）
           ├── 从 Apollo 读取 ops.* 配置
           ├── Docker build → push 到 Harbor
           └── kubectl apply → K3s
                  ├── Deployment + HPA（自动扩缩容）
                  ├── PDB（节点维护保护，≥2 副本时自动创建）
                  ├── Service（始终创建）
                  └── Ingress（仅在配置 appDomain 时创建）
```

> 执行环境准备（app.sh 上传、kubeconfig 分发、基础镜像推送、Harbor Secret）由 `setup-gitlab-runner start` 统一完成，本 skill 不涉及。

## GitLab CI 模板

| 文件 | 适用项目 |
|------|---------|
| `references/.gitlab-ci.yml` | 单体 Java 或前端项目 |
| `references/.gitlab-ci-aggregated.yml` | 聚合仓库（一仓多微服务） |
| `references/demo-backend/.gitlab-ci.yml` | Demo 后端项目（含示例 stages） |
| `references/demo-frontend/.gitlab-ci.yml` | Demo 前端项目（含示例 stages） |

## Apollo 配置机制

app.sh 执行时从 Apollo `tech.common` namespace 读取 `ops.*` 配置项生成 K8s YAML。**namespace 不存在时直接报错退出**，首次部署必须先导入 `tech.common` 模板（模板位于 `<skill_dir>/references/apollo-tech-common.properties`）。

**配置优先级**：项目专属 namespace > `tech.common` 公共 namespace

主要配置分组及关键约束：

| 配置组 | 关键项 | 重要约束 |
|--------|--------|---------|
| K8s 资源 | `ops.k8sReplicas`、`ops.appCpuLimit`、`ops.appMemoryLimit` | `appCpuLimit ≥ 0.2`（requests.cpu 硬编码 100m） |
| HPA | `ops.k8sReplicasMin`、`ops.k8sReplicasMax`、`ops.k8sTargetCPU` | min/max 须同时配置才启用 HPA |
| PDB | `ops.k8sPdbMinAvailable` | 必须 < replicas，否则 drain 永久阻塞；设 0 可显式禁用 |
| 域名 | `ops.appDomain` | 不配置则不创建 Ingress（Service 始终创建） |
| Java | `ops.javaVersion`、`ops.supportOtel`、`ops.otelMode`、`ops.javaCmdOptions` | `otelMode` 可选 `bridge`（SB 3.x 主力，Micrometer + OTel Bridge）或 `agent`（SB 2.x 兜底）；不要手动设置 -Xmx/-Xms |
| 前端 | `ops.nodejsVersion`、`ops.nodejsBuildCommand`、`ops.htmlPackageDirectory` | 运行时固定 nginx:1.27，nodejsVersion 仅用于构建 |
| Python | `ops.pythonVersion`、`ops.appPort`（必须）、`ops.pyStartCommand` | `appPort` 必须显式配置；`appMemoryLimit ≥ 256`；`pyStartCommand` 不能含双引号 |

> 完整配置项说明、部署示例、多语言示例见 **README.md**。
> `tech.common` 配置模板见 `references/apollo-tech-common.properties`。

## 参考文档

| 文档 | 用途 |
|------|------|
| `references/apollo-tech-common.properties` | Apollo 公共配置模板（首次部署导入） |
| `references/.gitlab-ci.yml` | Java 项目 Pipeline 模板 |
| `references/.gitlab-ci-aggregated.yml` | 聚合项目 Pipeline 模板 |
| `references/demo-backend/` | Demo 后端项目模板 |
| `references/demo-frontend/` | Demo 前端项目模板 |

## 踩坑记录规则

> 业务接入过程中遇到的问题，按以下流程处理：
> 1. **修复模板**：将 fix 写入 `references/` 配置文件或 `actions/*.md` 流程步骤
> 2. **记录 SKILL.md**：在本文件追加说明（仅记录无法自动化的操作风险和使用指引）
> 3. **记录 pitfalls.md**：追加踩坑条目，注明问题现象、根因和修复方案
