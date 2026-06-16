# Action: status

查询 edge-nginx 运行状态。

## 参数解析

### Step 0：--env 参数解析（B 类契约）

从用户指令中提取 --env 参数：
- 若未传入 → 默认 `nonprod`
- 若值为 `nonprod` 或 `prod` → 正常执行
- 若值非法 → 报错退出

### Step 1：查询容器状态

```bash
<SSH> docker ps --filter "name=tech-edge-nginx-${ENV}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### Step 2：查询资源使用

```bash
<SSH> docker stats --no-stream tech-edge-nginx-${ENV} 2>/dev/null || echo "容器未运行"
```

### Step 3：检查端口监听

```bash
<SSH> ss -tlnp | grep -E ":80|:443" | head -5
```

## 输出

```
==========================================
edge-nginx 状态
==========================================
环境: ${ENV}
容器名: tech-edge-nginx-${ENV}

容器状态:
${CONTAINER_STATUS}

端口监听:
${PORT_LIST}

资源使用:
${RESOURCE_USAGE}
==========================================
```

## 预期正常输出示例

```
NAMES                    STATUS                   PORTS
tech-edge-nginx-prod     Up 2 hours (healthy)     0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp

CONTAINER ID   NAME                  CPU %     MEM USAGE / LIMIT     MEM %     NET I/O           BLOCK I/O         PIDS
abc123def456   tech-edge-nginx-prod  0.01%     15.2MiB / 1GiB        1.52%     1.2MB / 850kB     2.1MB / 0B        5

LISTEN    0    511    0.0.0.0:80    0.0.0.0:*    users:(("nginx",pid=1234,fd=6))
LISTEN    0    511    0.0.0.0:443   0.0.0.0:*    users:(("nginx",pid=1234,fd=7))
```

> **注意**：使用 host 网络模式，端口直接由 nginx 进程绑定，不经过 docker-proxy。

## 状态判断

| 容器状态 | 说明 |
|---------|------|
| Up X minutes (healthy) | 正常运行 |
| Up X minutes (unhealthy) | 健康检查失败 |
| Exited (0) | 正常停止 |
| Exited (non-zero) | 异常停止 |
| 未找到 | 未部署 |
