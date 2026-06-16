# action: status — 查看 Grafana 运行状态

## 参数解析

> 继承主调用的 `--env` 参数，`ENV` = nonprod 或 prod。

## 步骤

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "docker ps \
    --filter 'name=tech-grafana-${ENV}' \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
```

---

## 补充：查看资源占用

```bash
docker stats \
  tech-grafana-${ENV} \
  --no-stream \
  --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
```
