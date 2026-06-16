# Action: stop

停止 edge-nginx 服务。

## 参数解析

### Step 0：--env 参数解析（B 类契约）

从用户指令中提取 --env 参数：
- 若未传入 → 默认 `nonprod`
- 若值为 `nonprod` 或 `prod` → 正常执行
- 若值非法 → 报错退出

### Step 1：确定容器名

| --env | 容器名 | 部署目录 |
|-------|--------|---------|
| nonprod | tech-edge-nginx-nonprod | /opt/tech-stack/edge-nginx-nonprod |
| prod | tech-edge-nginx-prod | /opt/tech-stack/edge-nginx-prod |

### Step 2：停止容器

```bash
<SSH> cd /opt/tech-stack/edge-nginx-${ENV} && docker compose stop
```

### Step 3：验证停止

```bash
<SSH> docker ps --filter "name=${CONTAINER_NAME}" --format "{{.Names}}: {{.Status}}"
```

若输出为空，表示容器已停止。

## 输出

```
==========================================
服务已停止
==========================================
环境: ${ENV}
容器名: ${CONTAINER_NAME}
==========================================
```

---

## 恢复服务

```bash
<SSH> cd /opt/tech-stack/edge-nginx-${ENV} && docker compose start
```

---

## 影响说明

停止后：
- 所有公网业务流量中断（*.${ENV}.web/api.renew.com 无法访问）
- HTTP 请求无响应
- HTTPS 请求无响应
- 健康检查端点 :8888/health 无响应

**恢复方式**：执行 `docker compose start` 或重新部署。
