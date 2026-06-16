# action: logs — 查看 Prometheus / Alertmanager 容器日志

## 参数解析

> 继承主调用的 `--env` 参数，`ENV` = nonprod 或 prod。

## 容器选择

若用户未在命令中指定容器名，询问：
```
请选择要查看的容器：
  1. prometheus    (tech-prometheus-${ENV})
  2. alertmanager  (tech-alertmanager-${ENV})
```

## 步骤

```bash
# prometheus（示例，其他容器同理）
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "docker logs tech-prometheus-${ENV} --tail 100 -f"
```

---

## 常见错误排查

| 错误关键词 | 含义 | 解决方法 |
|-----------|------|---------|
| `no such host` / `connection refused` (Prometheus scrape) | 目标服务不可达 | 检查 prometheus.yml 中的 targets 地址是否正确 |
| `Error loading config` (Prometheus) | prometheus.yml 语法错误 | 在容器内验证：`docker exec tech-prometheus-${ENV} promtool check config /etc/prometheus/prometheus.yml` |
| `Error loading config` (Alertmanager) | alertmanager.yml 语法错误 | 在容器内验证：`docker exec tech-alertmanager-${ENV} amtool check-config /etc/alertmanager/alertmanager.yml` |

## Prometheus 配置热重载

修改 `prometheus.yml` 后无需重启容器：
```bash
curl -X POST http://localhost:9090/-/reload
```
