# action: status — 查看 Prometheus + Alertmanager 运行状态

## 参数解析

> 继承主调用的 `--env` 参数，`ENV` = nonprod 或 prod。

## 步骤

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "docker ps \
    --filter 'name=tech-prometheus-${ENV}' \
    --filter 'name=tech-alertmanager-${ENV}' \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
```

---

## 补充：查看资源占用

```bash
docker stats \
  tech-prometheus-${ENV} tech-alertmanager-${ENV} \
  --no-stream \
  --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
```

## 补充：查看 Prometheus scrape 状态

访问 http://localhost:9090/targets 可查看所有抓取目标的健康状态。
