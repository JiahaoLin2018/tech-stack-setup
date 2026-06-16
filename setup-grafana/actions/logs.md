# action: logs — 查看 Grafana 容器日志

## 参数解析

> 继承主调用的 `--env` 参数，`ENV` = nonprod 或 prod。

## 步骤

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "docker logs tech-grafana-${ENV} --tail 100 -f"
```

---

## 常见错误排查

| 错误关键词 | 含义 | 解决方法 |
|-----------|------|---------|
| `permission denied` | 数据目录权限问题 | `chmod 777 /opt/tech-stack/grafana-${ENV}/data/grafana` |
| `GF_SECURITY_ADMIN_PASSWORD` 相关错误 | 密码配置问题 | 检查 `.env` 中 `GRAFANA_ADMIN_PASSWORD` 是否已设置 |
| `datasource not found` | 数据源后端未启动 | 确认 Prometheus/Tempo/Loki 容器已运行 |
| `connection refused` (数据源) | 数据源不可达 | 检查 `.env` 中数据源地址配置，确认对应服务已启动 |
