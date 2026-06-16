# Task 33 — GitLab Runner 非生产部署（一站式）

> 一站式部署非生产 CI/CD 执行环境（Runner 容器 + CI Job 环境）。对应 architecture-blueprint.md 第五部分阶段三 3-8。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-03（GitLab）+ task-05（Harbor）+ task-04（Nexus）+ task-27（K3s nonprod）+ task-32（OTel Collector nonprod）+ task-11/16/21/26（4 套 Consul）+ task-06（Apollo nonprod） |
| 环境要求 | Docker + Docker Compose；Docker daemon.json 含 `"insecure-registries": ["harbor.renew.com"]` |
| 注册凭证 | GitLab → Settings → CI/CD → Runners 获取的 `glrt-` 格式 Registration Token |

## 架构约束

- B 类域级共用（Runner tag = `non-prod`）
- 一站式吸收 CI Job 执行环境：app.sh / settings.xml / kubeconfig / 静态工具三件套（kubectl / jq / docker）/ OTel Java Agent jar
- OTel Java Agent v2.26.1 由本 task 统一管理：宿主机 `/opt/tech-stack/cicd/opentelemetry-javaagent.jar`，volumes 挂载到 CI 容器 `/opt/otel/`
- Runner 18.x 注册不接受 `--locked` / `--run-untagged` / `--tag-list`，必须在 GitLab UI 配置
- app.sh 的 env→domainEnv 映射：dev/sit/fat/uat → nonprod；prod → prod

## 一站式产出物（`/opt/tech-stack/cicd/`）

| 文件 | 来源 | 用途 |
|------|------|------|
| `app.sh` | references/app.sh + sed 替换 | CI Job 部署脚本 |
| `settings.xml` | references/settings.xml + sed 替换 | Maven 镜像到 Nexus |
| `kubeconfig` | task-27 K3s 生成 | `app.sh kubectl apply` 凭证 |
| `kubectl-bin` | 静态二进制下载 v1.32.0 | CI 容器内 K8s 客户端 |
| `jq-static` | jq 1.7.1 静态二进制 | CI 容器内 JSON 处理 |
| `docker-static` | 宿主机 docker CLI 静态版 | CI 容器内 docker push |
| `opentelemetry-javaagent.jar` | OTel Agent v2.26.1 下载 | Spring Boot 2.x 兜底接入 |

## 关键 .env 配置

| 变量 | 说明 |
|------|------|
| `RUNNER_ENV` | `nonprod` |
| `RUNNER_TAG` | `non-prod` |
| `GITLAB_URL` | `http://gitlab.renew.com` |
| `RUNNER_REGISTRATION_TOKEN` | `glrt-xxx`（从 GitLab UI 获取） |
| `HARBOR_PASSWORD` | Harbor robot account 密码（推荐） |
| `NEXUS_PASSWORD` | Nexus CI 用户密码（settings.xml sed 替换使用） |
| `RUNNER_NAME` | Runner 名称，默认 `gitlab-runner-01` |
| `RUNNER_CONCURRENT` | 默认 2，按 Pipeline 并发量按需调整 |
| `RUNNER_DOCKER_IMAGE` | 默认镜像，默认 `maven:3.9-eclipse-temurin-21` |
| `RUNNER_DOCKER_PULL_POLICY` | 默认 `if-not-present` |
| `RUNNER_DOCKER_PRIVILEGED` | 默认 `false`（socket 挂载即可，无需 DinD） |

## 部署命令

```bash
/setup-gitlab-runner start --host <RUNNER_NONPROD_IP> --env nonprod --user <USER> --password <PASS>
/setup-gitlab-runner verify --host <RUNNER_NONPROD_IP> --env nonprod --user <USER> --password <PASS>
```

## 验证标准

- [ ] GitLab → Settings → CI/CD → Runners 显示 Runner 在线，tag = `non-prod`
- [ ] `gitlab-runner verify` 返回 `is alive`
- [ ] `/opt/tech-stack/cicd/` 三件套齐全：`app.sh` / `settings.xml` / `kubeconfig` / `kubectl-bin` / `jq-static` / `docker-static` / `opentelemetry-javaagent.jar`
- [ ] CI 镜像中 `kubectl version --client && jq --version && docker --version` 全部通过
- [ ] Harbor 中已存在基础镜像（Runner 已推送 JDK / Nginx / Python 等）
- [ ] Docker daemon.json 含 `harbor.renew.com` 在 insecure-registries

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 4 GB+ | 2-4 核 | 100 GB+（CI 缓存 + 镜像构建空间） |

## 并行说明

必须在 task-03/04/05/27 + LGT（28~32）+ Consul（11/16/21/26）+ Apollo（06）全部就绪后部署。

## 注意事项

- 容器名按 env 切换（`tech-gitlab-runner-nonprod`），操作时必须传对应 `--env`
- 静态二进制不可省（K3s symlink + 动态链接库问题）
- Runner tag 路由禁止误投递：`tags: [non-prod]` 必须在 `.gitlab-ci.yml` 中明确声明
- 生产建议用 Harbor Robot Account（只读）替代 admin 密码

## 后续步骤

- task-34（CI/CD demo）端到端验证 Pipeline 链路
- 业务项目按 `setup-cicd integrate` 模板接入
