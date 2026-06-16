# action: register — 向 GitLab 注册 Runner

## 前提条件

1. GitLab Runner 容器已启动（执行过 `start` action）
2. 已从 GitLab 获取 Registration Token（Settings → CI/CD → Runners → New Project Runner）

## 步骤

### 步骤 1：读取 .env 配置

```bash
SSH_CMD "cat /opt/tech-stack/gitlab-runner/.env"
```

检查以下配置项：
- `GITLAB_URL` — GitLab 实例地址
- `RUNNER_REGISTRATION_TOKEN` — 注册 Token（必须已设置，非 `CHANGE_ME_*`）

若 Token 未设置，提示用户：
```
请先在 .env 中设置 RUNNER_REGISTRATION_TOKEN：
  SSH_CMD "vi /opt/tech-stack/gitlab-runner/.env"

或在命令行提供：
  /setup-gitlab-runner register --host <ip> --token <your-token>
```

### 步骤 2：验证 GitLab 连通性

```bash
SSH_CMD "docker exec tech-gitlab-runner-${RUNNER_ENV} wget -q -O /dev/null ${GITLAB_URL} && echo 'GitLab 可达' || echo 'GitLab 不可达'"
```

- 若不可达，检查：
  1. DNS 是否配置正确（能解析 gitlab.renew.com）
  2. GitLab 服务是否正常运行

### 步骤 3：执行注册命令

```bash
SSH_CMD "docker exec tech-gitlab-runner-${RUNNER_ENV} gitlab-runner register \
  --non-interactive \
  --url ${GITLAB_URL} \
  --token ${RUNNER_REGISTRATION_TOKEN} \
  --name \"${RUNNER_NAME}\" \
  --executor docker \
  --docker-image \"${RUNNER_DOCKER_IMAGE}\" \
  --docker-pull-policy \"${RUNNER_DOCKER_PULL_POLICY}\" \
  --docker-privileged=${RUNNER_DOCKER_PRIVILEGED:-false} \
  --docker-volumes \"/cache\" \
  --docker-volumes \"/var/run/docker.sock:/var/run/docker.sock\" \
  --docker-volumes \"/opt/tech-stack/cicd:/opt/tech-stack/cicd:ro\" \
  --docker-volumes \"/opt/tech-stack/cicd/kubectl-bin:/usr/local/bin/kubectl:ro\" \
  --docker-volumes \"/opt/tech-stack/cicd/jq-static:/usr/local/bin/jq:ro\" \
  --docker-volumes \"/opt/tech-stack/cicd/docker-static:/usr/local/bin/docker:ro\" \
  --docker-volumes \"/opt/tech-stack/cicd/settings.xml:/root/.m2/settings.xml:ro\" \
  --docker-volumes \"/opt/tech-stack/cicd/opentelemetry-javaagent.jar:/opt/otel/opentelemetry-javaagent.jar:ro\""
```

**关键参数说明**：
- `--non-interactive`：非交互模式
- `--token`：GitLab Runner Token（glrt- 格式，GitLab 16+ 新方式）
- `--docker-volumes`：挂载缓存目录、Docker socket、CI/CD 目录、静态工具、Maven 配置、OTel Agent

**挂载说明**：

| 挂载路径 | 容器内目标 | 用途 |
|---------|----------|------|
| `/cache` | `/cache` | GitLab CI 缓存目录 |
| `/var/run/docker.sock` | `/var/run/docker.sock` | CI 作业可构建/推送镜像 |
| `/opt/tech-stack/cicd` | `/opt/tech-stack/cicd:ro` | app.sh、kubeconfig、settings.xml 等整体只读挂载 |
| `cicd/kubectl-bin` | `/usr/local/bin/kubectl:ro` | 静态 kubectl v1.32.0（避免 K3s symlink 问题） |
| `cicd/jq-static` | `/usr/local/bin/jq:ro` | 静态 jq 1.7.1（避免动态链接库依赖） |
| `cicd/docker-static` | `/usr/local/bin/docker:ro` | 宿主机 docker CLI |
| `cicd/settings.xml` | `/root/.m2/settings.xml:ro` | Maven 配置（Nexus 私服镜像 + 认证） |
| `cicd/opentelemetry-javaagent.jar` | `/opt/otel/opentelemetry-javaagent.jar:ro` | OTel Java Agent v2.26.1（agent 模式必须） |

> **Runner 18.x 重要限制**：`--tag-list`、`--run-untagged`、`--locked` 等参数已从 register 命令移除，必须在 GitLab UI 中配置（Settings → CI/CD → Runners → 编辑 Runner）。

### 步骤 4：验证注册结果

```bash
SSH_CMD "docker exec tech-gitlab-runner-${RUNNER_ENV} gitlab-runner list"
```

输出应显示已注册的 Runner：
```
gitlab-runner-01   Token=xxx   Executor=docker URL=http://gitlab.renew.com
```

### 步骤 5：检查 Runner 在 GitLab 中的状态

```bash
SSH_CMD "docker exec tech-gitlab-runner-${RUNNER_ENV} gitlab-runner verify"
```

输出应显示 `Runner is alive`。

### 步骤 6：设置全局并发数

`concurrent` 是全局配置，无法通过 `register` 命令设置，需注册后修改 `config.toml`：

```bash
SSH_CMD "sed -i 's/^concurrent = .*/concurrent = ${RUNNER_CONCURRENT:-2}/' /opt/tech-stack/gitlab-runner/config/config.toml"
```

### 步骤 7：展示注册结果

```
✅ GitLab Runner 注册成功！

Runner 名称：  ${RUNNER_NAME}
GitLab URL：   ${GITLAB_URL}
Executor：     docker
默认镜像：     ${RUNNER_DOCKER_IMAGE}
并发数：       ${RUNNER_CONCURRENT}

挂载到 CI Job 容器：
├── /cache                                                          # GitLab CI 缓存
├── /var/run/docker.sock                                            # Docker 镜像构建
├── /opt/tech-stack/cicd                          (ro)              # app.sh / kubeconfig / 工具整体目录
├── cicd/kubectl-bin    → /usr/local/bin/kubectl  (ro)              # 静态 kubectl
├── cicd/jq-static      → /usr/local/bin/jq       (ro)              # 静态 jq
├── cicd/docker-static  → /usr/local/bin/docker   (ro)              # 宿主机 docker CLI
├── cicd/settings.xml   → /root/.m2/settings.xml  (ro)              # Maven 配置
└── cicd/opentelemetry-javaagent.jar
                        → /opt/otel/opentelemetry-javaagent.jar (ro)  # OTel Agent v2.26.1

下一步：
1. 在 GitLab 中查看 Runner 状态：Settings → CI/CD → Runners
2. 确保 CI 作业使用的镜像在 Runner 可访问（配置镜像加速器或使用 Harbor）
3. 创建 .gitlab-ci.yml 测试流水线

配置文件位置：/opt/tech-stack/gitlab-runner/config/config.toml
```

---

## 常见问题处理

### Runner 18.x 参数限制

**现象**：`Runner configuration other than name and executor configuration is reserved`

**原因**：Runner 18.x（含 latest alpine）使用 runner authentication token（glrt-）时，`--locked`、`--run-untagged`、`--tag-list` 等参数只能在 GitLab UI 创建 Runner 时设置，不能通过 register 命令指定。

**修复**：register 命令去掉这些参数，仅保留 executor 相关配置：
```bash
gitlab-runner register \
  --non-interactive \
  --url <GITLAB_URL> \
  --token <TOKEN> \
  --name <NAME> \
  --executor docker \
  --docker-image <IMAGE> \
  --docker-pull-policy if-not-present \
  --docker-privileged=false \
  --docker-volumes "/cache" \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
  --docker-volumes "/opt/tech-stack/cicd:/opt/tech-stack/cicd:ro"
```

Tags、run-untagged、locked 等在 GitLab UI → Settings → CI/CD → Runners → 编辑 Runner 中配置。

### Token 格式错误

**现象**：`This endpoint is deprecated` 或 `invalid token`

**原因**：GitLab 16+ 使用新的 registration flow：
- 旧方式：`--registration-token`（已弃用）
- 新方式：`--token`（glrt- 格式）

**修复**：使用 GitLab UI 生成的新 Token：
1. GitLab → Settings → CI/CD → Runners
2. 点击 "New Project Runner"
3. 选择 Platform（Linux）、Tags
4. 点击 "Create runner"
5. 复制生成的 Token（glrt- 开头）

### GitLab URL 不可达

**现象**：`dial tcp: lookup gitlab.renew.com: no such host`

**修复**：
```bash
# 方案一：确保 DNS 配置正确
SSH_CMD "cat /etc/resolv.conf | grep nameserver"

# 方案二：添加 hosts 映射（临时）
SSH_CMD "echo '<gitlab-ip> gitlab.renew.com' >> /etc/hosts"

# 方案三：在注册时添加 --docker-add-host
docker exec tech-gitlab-runner-${RUNNER_ENV} gitlab-runner register \
  --docker-add-host "gitlab.renew.com:<gitlab-ip>" \
  ...
```

### Docker socket 权限问题

**现象**：CI 作业中 `docker build` 报 `permission denied`

**修复**：
```bash
# 临时修复（重启后失效）
SSH_CMD "chmod 666 /var/run/docker.sock"

# 永久修复（重建容器）
SSH_CMD "cd /opt/tech-stack/gitlab-runner && docker compose down"
SSH_CMD "usermod -aG docker $(id -u gitlab-runner 2>/dev/null || echo root)"
SSH_CMD "docker compose up -d"
```
