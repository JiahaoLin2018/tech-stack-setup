# action: verify — 验证 CI/CD 执行环境

> 验证 Runner 容器 + CI Job 执行环境（/opt/tech-stack/cicd/）是否就绪。可选 `--app-id` 进一步检查指定应用的部署环境。
>
> **前置条件**：`references/.env` 已配置 `HARBOR_PASSWORD`

## 参数

- `--app-id <appId>`: 应用 ID（可选，检查业务应用部署环境时使用）
- `--env <env>`: 部署环境（默认: fat）

## 前置：从 .env 读取密码

```bash
HARBOR_PASSWORD=$(grep '^HARBOR_PASSWORD=' ${CLAUDE_SKILL_DIR}/references/.env | cut -d'=' -f2)

if [ -z "${HARBOR_PASSWORD}" ] || [ "${HARBOR_PASSWORD}" = "CHANGE_ME_HARBOR_PASSWORD" ]; then
  echo "[ERROR] Harbor 密码未配置，请先编辑 references/.env"
  exit 1
fi
```

## 步骤

### 步骤 1：检查 Runner 容器运行状态

```bash
SSH_CMD "docker inspect tech-gitlab-runner-${RUNNER_ENV} --format '{{.State.Status}}' 2>/dev/null || echo 'NOT_FOUND'"
```

- `running` → 继续验证
- `exited` → 提示 "容器已停止，请先执行 start"
- `NOT_FOUND` → 提示 "容器不存在，请先执行 start"

### 步骤 2：检查 Runner 版本与 GitLab 连接

```bash
SSH_CMD "docker exec tech-gitlab-runner-${RUNNER_ENV} gitlab-runner --version"
SSH_CMD "docker exec tech-gitlab-runner-${RUNNER_ENV} gitlab-runner verify"
```

- `is alive` → 连接正常
- `could not contact` → 连接失败，检查网络/DNS

### 步骤 3：检查 Docker socket 与 Runner 配置

```bash
SSH_CMD "docker exec tech-gitlab-runner-${RUNNER_ENV} ls -la /var/run/docker.sock 2>/dev/null && echo 'Docker socket 已挂载' || echo 'Docker socket 未挂载'"
SSH_CMD "cat /opt/tech-stack/gitlab-runner/config/config.toml 2>/dev/null | head -20 || echo '配置文件不存在'"
```

### 步骤 4：检查 CI Job 执行环境文件（/opt/tech-stack/cicd/）

```bash
# app.sh / settings.xml / kubeconfig
SSH_CMD "ls -la /opt/tech-stack/cicd/app.sh /opt/tech-stack/cicd/settings.xml /opt/tech-stack/cicd/kubeconfig"
SSH_CMD "test -x /opt/tech-stack/cicd/app.sh && echo 'APP_SH_OK' || echo 'APP_SH_NOT_EXECUTABLE'"

# 静态工具三件套
SSH_CMD "ls -la /opt/tech-stack/cicd/kubectl-bin /opt/tech-stack/cicd/jq-static /opt/tech-stack/cicd/docker-static"
```

### 步骤 5：在 CI 容器内模拟验证静态工具

```bash
SSH_CMD "docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /opt/tech-stack/cicd/kubectl-bin:/usr/local/bin/kubectl:ro \
  -v /opt/tech-stack/cicd/jq-static:/usr/local/bin/jq:ro \
  -v /opt/tech-stack/cicd/docker-static:/usr/local/bin/docker:ro \
  maven:3.9-eclipse-temurin-21 bash -c \
  'kubectl version --client && jq --version && docker --version && echo TOOLS_OK'"
```

### 步骤 6：检查 Runner 容器挂载

```bash
SSH_CMD "docker inspect tech-gitlab-runner-${RUNNER_ENV} --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}' | grep cicd"
```

预期输出包含：

```
/opt/tech-stack/cicd/kubeconfig -> /opt/tech-stack/cicd/kubeconfig
/opt/tech-stack/cicd/app.sh -> /opt/tech-stack/cicd/app.sh
/opt/tech-stack/cicd/settings.xml -> /opt/tech-stack/cicd/settings.xml
```

### 步骤 7：检查 K3s 资源

```bash
# K3s 连接
SSH_CMD "kubectl --kubeconfig=/opt/tech-stack/cicd/kubeconfig get nodes"

# namespace（可能不存在，首次 Pipeline 后由 app.sh 创建）
SSH_CMD "kubectl get namespace ${ENV:-fat} 2>/dev/null || echo 'NOT_FOUND'"

# Harbor 镜像拉取密钥（可能不存在，首次 Pipeline 后由 app.sh 创建）
SSH_CMD "kubectl get secret harbor-registry -n ${ENV:-fat} -o jsonpath='{.data.\.dockerconfigjson}' 2>/dev/null | base64 -d | jq -r '.auths | keys[]' || echo 'NOT_FOUND'"
```

> namespace 和 harbor-registry Secret 由 app.sh 在首次 Pipeline 时自动创建（幂等）。若返回 `NOT_FOUND`，说明尚未有应用部署到该环境。

### 步骤 8：检查 Harbor 基础镜像

```bash
# JDK
SSH_CMD "curl -s -o /dev/null -w '%{http_code}' -u admin:${HARBOR_PASSWORD} \
  'http://harbor.renew.com/api/v2.0/projects/library/repositories/jdk/artifacts'"

# Nginx
SSH_CMD "curl -s -o /dev/null -w '%{http_code}' -u admin:${HARBOR_PASSWORD} \
  'http://harbor.renew.com/api/v2.0/projects/library/repositories/nginx/artifacts'"

# Python
SSH_CMD "curl -s -o /dev/null -w '%{http_code}' -u admin:${HARBOR_PASSWORD} \
  'http://harbor.renew.com/api/v2.0/projects/library/repositories/python/artifacts'"
```

- 返回 200 → 镜像存在
- 返回 404 → 需要推送基础镜像（执行 `/setup-gitlab-runner start`）

### 步骤 9：检查指定应用部署环境（仅当 --app-id 指定时）

```bash
if [ -n "${APP_ID}" ]; then
  # 检查 Apollo 配置（fat 环境，经 infra-nginx 代理到内部端口 8603）
  curl -s "http://apollo-config-${ENV:-fat}.renew.com/configs/${APP_ID}/default/tech.common" | jq -r '.configurations | keys[]'

  # 检查 DNS 解析（在集群内用 busybox 测）
  SSH_CMD "kubectl run test-dns-${APP_ID} --image=busybox:1.36 --rm -it --restart=Never -n ${ENV:-fat} -- nslookup mysql-${ENV:-fat}.renew.com"

  # 检查已有部署
  SSH_CMD "kubectl get deployment ${APP_ID} -n ${ENV:-fat} -o wide 2>/dev/null || echo 'NOT_DEPLOYED'"
fi
```

### 步骤 10：输出验证报告

```
═══════════════════════════════════════════════════════════════
【CI/CD 执行环境验证报告】${ENV:-fat}
═══════════════════════════════════════════════════════════════

【Runner 容器】
| 检查项 | 状态 | 说明 |
|--------|------|------|
| 容器运行 | ✅ | Running |
| Runner 版本 | ✅ | v17.x / v18.x |
| GitLab 连接 | ✅ | alive |
| Docker socket | ✅ | 已挂载 |
| config.toml | ✅ | 存在 |

【CI Job 执行环境（/opt/tech-stack/cicd/）】
| 检查项 | 状态 | 说明 |
|--------|------|------|
| app.sh | ✅ | 存在且可执行 |
| settings.xml | ✅ | 存在 |
| kubeconfig | ✅ | 存在 |
| kubectl-bin | ✅ | v1.32.0 |
| jq-static | ✅ | 1.7.1 |
| docker-static | ✅ | 可用 |
| 容器挂载三件套 | ✅ | 已挂载到容器 PATH |

【K3s 资源】
| 检查项 | 状态 | 说明 |
|--------|------|------|
| K3s 连接 | ✅ | N node ready |
| Namespace | ℹ️ | ${ENV:-fat}（首次 Pipeline 后由 app.sh 创建）|
| Harbor 密钥 | ℹ️ | harbor-registry（首次 Pipeline 后由 app.sh 创建）|

【Harbor 基础镜像】
| 镜像 | 状态 |
|------|------|
| library/jdk:21 | ✅ |
| library/nginx:1.27 | ✅ |
| library/python:3.11 | ✅ |

───────────────────────────────────────────────────────────────
【应用部署环境】${APP_ID}（仅在 --app-id 指定时）
───────────────────────────────────────────────────────────────
| 检查项 | 状态 | 说明 |
|--------|------|------|
| Apollo 配置 | ✅ | tech.common 配置完整 |
| DNS 解析 | ✅ | *.renew.com 解析正常 |
| Deployment | ✅ | 2/2 Running |
| HPA | ✅ | 2-5 副本 |
| Ingress | ✅ | ${APP_ID}.${ENV:-fat}.api.renew.com |

═══════════════════════════════════════════════════════════════
✅ 环境就绪，可以执行 CI/CD Pipeline
```

---

## 常见问题修复

### Runner 容器未运行

```bash
docker logs tech-gitlab-runner
# 重启容器
cd /opt/tech-stack/gitlab-runner && docker compose up -d
```

### kubectl/jq 找不到

检查 Runner config.toml volumes 是否包含静态二进制挂载：

```toml
volumes = [
  "/cache",
  "/var/run/docker.sock:/var/run/docker.sock",
  "/opt/tech-stack/cicd:/opt/tech-stack/cicd:ro",
  "/opt/tech-stack/cicd/kubectl-bin:/usr/local/bin/kubectl:ro",
  "/opt/tech-stack/cicd/jq-static:/usr/local/bin/jq:ro",
  "/opt/tech-stack/cicd/docker-static:/usr/local/bin/docker:ro",
  "/opt/tech-stack/cicd/settings.xml:/root/.m2/settings.xml:ro"
]
```

静态二进制由 `/setup-gitlab-runner start` 自动下载。

### Harbor 密钥不存在

```bash
kubectl create secret docker-registry harbor-registry \
  --docker-server=harbor.renew.com \
  --docker-username=admin \
  --docker-password=${HARBOR_PASSWORD} \
  -n ${ENV:-fat} --dry-run=client -o yaml | kubectl apply -f -
```

### 基础镜像不存在

```bash
# 重新执行 start（幂等，会跳过已存在镜像）
/setup-gitlab-runner start --host <runner-ip>
```

### DNS 解析失败

检查 CoreDNS 自定义转发配置（持久化在 coredns-custom 中，重启 K3s 不会丢失）：

```bash
kubectl get configmap coredns-custom -n kube-system -o yaml
```

若 coredns-custom 不存在，重新应用：

```bash
kubectl apply -f /tmp/coredns-custom.yaml
kubectl rollout restart deployment coredns -n kube-system
```

---

## 故障排查清单

| 现象 | 可能原因 | 排查命令 |
|------|---------|---------|
| 容器未运行 | 未启动或崩溃 | `docker logs tech-gitlab-runner-${RUNNER_ENV}` |
| GitLab 不可达 | DNS 配置错误 | `docker exec tech-gitlab-runner-${RUNNER_ENV} nslookup gitlab.renew.com` |
| Docker 权限不足 | socket 权限 | `ls -la /var/run/docker.sock` |
| Runner 未注册 | 未执行 register | `docker exec tech-gitlab-runner-${RUNNER_ENV} gitlab-runner list` |
| kubectl 报错 | 挂载路径错误或 kubeconfig 缺失 | `ls /opt/tech-stack/cicd/` |
| Harbor secret 缺失 | 首次 Pipeline 未执行 | `kubectl get secret harbor-registry -n fat`（由 app.sh 创建） |

---

## Harbor 镜像拉取密钥说明

### 认证流程

```
1. Kubelet 拉取镜像
2. 读取 namespace 中的 harbor-registry secret
3. 使用 username/password 登录 Harbor
4. 拉取镜像 harbor.renew.com/library/app:tag
```

### 生产环境建议

使用 Harbor Robot Account（只读权限）替代 admin 密码：

```bash
# 1. 在 Harbor 创建 Robot Account
#    Harbor UI → 项目 → Robot Accounts → New Robot

# 2. 使用 Robot Token 创建密钥
kubectl create secret docker-registry harbor-registry \
  --docker-server=harbor.renew.com \
  --docker-username='robot$library+ci-bot' \
  --docker-password='<robot-token>' \
  -n fat
```
