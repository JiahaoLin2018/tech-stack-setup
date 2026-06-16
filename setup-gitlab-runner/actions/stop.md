# action: stop — 停止 GitLab Runner

## 步骤

```bash
SSH_CMD "cd /opt/tech-stack/gitlab-runner && docker compose stop"
```

执行后确认：

```bash
SSH_CMD "docker ps --filter name=tech-gitlab-runner-${RUNNER_ENV}"
```

无输出行表示容器已成功停止。

---

## 恢复服务

```bash
SSH_CMD "cd /opt/tech-stack/gitlab-runner && docker compose start"
```

---

## 数据保留说明

- 容器停止后数据目录 `/opt/tech-stack/gitlab-runner/config/` 保留
- 已注册的 Runner 配置不会丢失
- 重新 `start` 后无需重新注册
