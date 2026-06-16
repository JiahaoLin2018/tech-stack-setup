# action: stop — 停止 infra-nginx

## 步骤

```bash
SSH_CMD "cd /opt/tech-stack/infra-nginx && docker compose stop"
```

执行后确认：

```bash
# 本地
docker ps --filter name=tech-infra-nginx

# 远程
SSH_CMD "docker ps --filter name=tech-infra-nginx"
```

无输出行表示容器已成功停止。

---

## 恢复服务

```bash
cd /opt/tech-stack/infra-nginx && docker compose start
```

---

## 影响说明

停止后：
- 所有 Web UI 无法通过域名访问
- GitLab SSH 无法通过 :2222 访问
- Nexus Docker Registry 无法通过 :8082 访问
