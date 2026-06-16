# Task 48 — GitLab Runner 生产部署（一站式）

> 一站式部署生产 CI/CD 执行环境。对应 architecture-blueprint.md 第五部分阶段四 4-10。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-03（GitLab）+ task-05（Harbor）+ task-04（Nexus）+ task-41（K3s prod）+ task-46（OTel Collector prod）+ task-40（Consul prod）+ task-47（Apollo prod） |
| 环境要求 | 生产网段独立节点；Docker daemon.json 含 `harbor.renew.com` insecure-registries |
| 注册凭证 | GitLab → Settings → CI/CD → Runners 获取的 `glrt-` Token |

## 架构约束

- B 类域级共用（Runner tag = `prod`），生产网段独立部署，与非生产物理隔离
- 一站式吸收 CI Job 执行环境（与 task-33 nonprod 结构一致）
- OTel Java Agent v2.26.1 由本 task 统一管理：宿主机 `/opt/tech-stack/cicd/opentelemetry-javaagent.jar`，volumes 挂载到 CI 容器 `/opt/otel/`
- Runner 18.x 注册不接受 `--locked` / `--run-untagged` / `--tag-list`，必须在 GitLab UI 配置
- app.sh 的 env→domainEnv 映射对 prod 生效：env=prod → domainEnv=prod，OTLP endpoint = `http://otel-prod.renew.com:4317`
- `apollo.meta=http://apollo-config-prod.renew.com`（默认走 infra-nginx :80 反代到 :8605；如生产已上云到公有云 VPC，start 步骤 6.0 会触发 AskUserQuestion 切换为 `:8605` 直连模式）

## 一站式产出物（`/opt/tech-stack/cicd/`）

| 文件 | 说明 |
|------|------|
| `app.sh` | CI Job 部署脚本（同 task-33） |
| `settings.xml` | Maven 镜像到 Nexus |
| `kubeconfig` | task-41 K3s prod 生成 |
| `kubectl-bin` / `jq-static` / `docker-static` | 静态二进制三件套 |
| `opentelemetry-javaagent.jar` | OTel Agent v2.26.1 |

## 关键 .env 配置

| 变量 | 值 |
|------|---|
| `RUNNER_ENV` | `prod` |
| `RUNNER_TAG` | `prod` |
| `GITLAB_URL` | `http://gitlab.renew.com`（跨网段访问，需打通防火墙）|
| `RUNNER_REGISTRATION_TOKEN` | `glrt-xxx`（生产专用 Token） |
| `HARBOR_PASSWORD` | Harbor robot account 密码 |
| `NEXUS_PASSWORD` | Nexus CI 用户密码（settings.xml sed 替换使用） |
| `RUNNER_NAME` | Runner 名称，默认 `gitlab-runner-01` |
| `RUNNER_CONCURRENT` | 默认 2，按 Pipeline 并发量按需调整 |
| `RUNNER_DOCKER_IMAGE` | 默认镜像，默认 `maven:3.9-eclipse-temurin-21` |
| `RUNNER_DOCKER_PULL_POLICY` | 默认 `if-not-present` |
| `RUNNER_DOCKER_PRIVILEGED` | 默认 `false` |

## 部署命令

```bash
/setup-gitlab-runner start --host <RUNNER_PROD_IP> --env prod --user <USER> --password <PASS>
/setup-gitlab-runner verify --host <RUNNER_PROD_IP> --env prod --user <USER> --password <PASS>
```

## 验证标准

- [ ] GitLab → Runners 显示 Runner 在线，tag = `prod`
- [ ] `gitlab-runner verify` 返回 `is alive`
- [ ] cicd 三件套齐全
- [ ] Harbor 中已存在生产基础镜像（Runner 已推送）
- [ ] 生产 K3s Namespace `prod` 可被 kubeconfig 访问

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 4 GB+ | 2-4 核 | 100 GB+ |

## 并行说明

必须在 task-03/04/05/41/46/40/47 全部就绪后部署。

## 注意事项

- 生产 Runner 必须独立节点，与非生产无任何互通
- Pipeline 中 `tags: [prod]` 必须明确声明，禁止误投递
- Harbor robot account 推荐用于生产（避免 admin 密码外泄）
- 生产部署前建议代码审计 + 灰度发布策略

## 后续步骤

- task-49（edge-nginx prod）放行公网流量
- task-50（上线验证）
