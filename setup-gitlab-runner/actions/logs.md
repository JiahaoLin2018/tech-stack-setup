# action: logs — 查看 GitLab Runner 日志

## 步骤

### 步骤 1：查看最近日志（默认 100 行）

```bash
SSH_CMD "docker logs --tail 100 tech-gitlab-runner-${RUNNER_ENV}"
```

### 步骤 2：（可选）实时跟踪日志

询问用户是否实时跟踪：
```
是否实时跟踪日志？(y/n)
```

若确认：
```bash
SSH_CMD "docker logs -f --tail 50 tech-gitlab-runner-${RUNNER_ENV}"
```

### 步骤 3：（可选）按时间范围查看

```bash
# 最近 1 小时
SSH_CMD "docker logs --since 1h tech-gitlab-runner-${RUNNER_ENV}"

# 指定时间之后
SSH_CMD "docker logs --since '2024-01-01T00:00:00' tech-gitlab-runner-${RUNNER_ENV}"
```

---

## 日志关键字

| 关键字 | 含义 | 建议操作 |
|--------|------|---------|
| `ERROR` | 错误信息 | 检查具体错误原因 |
| `WARNING` | 警告信息 | 关注潜在问题 |
| `is alive` | Runner 连接正常 | 无需处理 |
| `could not contact` | 无法连接 GitLab | 检查网络/DNS |
| `permission denied` | 权限不足 | 检查 Docker socket 权限 |
| `Job succeeded` | 作业执行成功 | 无需处理 |
| `Job failed` | 作业执行失败 | 查看 CI 日志定位原因 |
