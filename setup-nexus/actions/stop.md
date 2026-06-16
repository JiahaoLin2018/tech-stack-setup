# action: stop — 停止 Nexus

## 步骤

```bash
SSH_CMD "cd /opt/tech-stack/nexus && docker compose stop"
```

执行后确认：

```bash
# 本地
docker ps --filter name=tech-nexus

# 远程
SSH_CMD "docker ps --filter name=tech-nexus"
```

无输出行表示容器已成功停止。

> 注意：Nexus 数据（所有已上传的 Maven 制品）持久化在 `data/` 目录中，重启后完全恢复。
