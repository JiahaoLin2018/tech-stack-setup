# action: status — 查看 GitLab Runner 状态

## 步骤

### 步骤 1：查看容器状态

```bash
SSH_CMD "docker ps -a --filter 'name=tech-gitlab-runner-${RUNNER_ENV}' --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
```

### 步骤 2：查看 Runner 进程状态

```bash
SSH_CMD "docker exec tech-gitlab-runner-${RUNNER_ENV} gitlab-runner --version 2>/dev/null || echo 'Runner 未运行'"
```

### 步骤 3：查看已注册的 Runner 列表

```bash
SSH_CMD "docker exec tech-gitlab-runner-${RUNNER_ENV} gitlab-runner list 2>/dev/null || echo '无已注册的 Runner'"
```

### 步骤 4：检查 Runner 与 GitLab 的连接

```bash
SSH_CMD "docker exec tech-gitlab-runner-${RUNNER_ENV} gitlab-runner verify 2>/dev/null || echo '无法验证'"
```

### 步骤 5：展示完整状态

```
GitLab Runner 状态

容器：
  名称：tech-gitlab-runner-${RUNNER_ENV}
  状态：<Running/Exited>

Runner：
  版本：<version>
  已注册：<是/否>

连接状态：
  GitLab URL：<url>
  状态：<alive/unreachable>

配置文件：/opt/tech-stack/gitlab-runner/config/config.toml
```
