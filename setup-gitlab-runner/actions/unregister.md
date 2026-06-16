# action: unregister — 从 GitLab 注销 Runner

## 说明

注销 Runner 会将其从 GitLab 中移除，不再接收作业。如需重新使用，需要重新注册。

## 步骤

### 步骤 1：查看当前注册的 Runner

```bash
SSH_CMD "docker exec tech-gitlab-runner-${RUNNER_ENV} gitlab-runner list"
```

输出示例：
```
gitlab-runner-01   Token=xxx   Executor=docker URL=http://gitlab.renew.com
```

### 步骤 2：确认注销操作

询问用户：
```
确认要注销 Runner 吗？
- 注销后 Runner 将不再接收作业
- 需要重新注册才能使用
- 配置文件 config.toml 中的 Token 将被清除

输入 Runner 名称确认注销（或输入 'cancel' 取消）：
```

### 步骤 3：执行注销

```bash
# 方式一：注销指定 Runner
SSH_CMD "docker exec tech-gitlab-runner-${RUNNER_ENV} gitlab-runner unregister --name ${RUNNER_NAME}"

# 方式二：注销所有 Runner
SSH_CMD "docker exec tech-gitlab-runner-${RUNNER_ENV} gitlab-runner unregister --all-runners"
```

### 步骤 4：验证注销结果

```bash
SSH_CMD "docker exec tech-gitlab-runner-${RUNNER_ENV} gitlab-runner list"
```

输出应为空，或不再显示已注销的 Runner。

### 步骤 5：展示结果

```
✅ GitLab Runner 已注销

Runner：${RUNNER_NAME}
状态：已从 GitLab 移除

下一步：
- 如需重新使用，执行：/setup-gitlab-runner register --host ${HOST}
- 在 GitLab UI 中确认 Runner 已移除：Settings → CI/CD → Runners
```

---

## 注意事项

1. **注销 vs 暂停**：
   - 注销：永久移除，需要重新注册
   - 暂停：临时停止接收作业，可在 GitLab UI 中恢复

2. **暂停 Runner**（不移除）：
   ```bash
   # 在 GitLab UI 中操作
   Settings → CI/CD → Runners → 点击 Runner → Pause
   ```

3. **清理配置文件**（可选）：
   ```bash
   SSH_CMD "rm -f /opt/tech-stack/gitlab-runner/config/config.toml"
   ```
