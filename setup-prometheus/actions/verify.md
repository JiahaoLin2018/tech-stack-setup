# action: verify — 验证 Prometheus + Alertmanager 服务

## 参数解析

> 继承主调用的 `--env` 参数，`ENV` = nonprod 或 prod。

## 步骤

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  source /opt/tech-stack/prometheus-${ENV}/.env
  PROM_PORT=\${PROMETHEUS_PORT:-9090}
  AM_PORT=\${ALERTMANAGER_PORT:-9093}

  echo '=== 验证 Prometheus ==='
  curl -sf http://localhost:\${PROM_PORT}/-/healthy && echo 'Prometheus 正常' || echo 'Prometheus 未就绪'

  echo ''
  echo '=== 验证 Alertmanager ==='
  curl -sf http://localhost:\${AM_PORT}/-/healthy && echo 'Alertmanager 正常' || echo 'Alertmanager 未就绪'
"
```

---

## 访问地址汇总

| 服务 | 地址 | 说明 |
|------|------|------|
| Prometheus | http://\<HOST\>:\<PROMETHEUS_PORT\> | 指标查询与规则管理 |
| Alertmanager | http://\<HOST\>:\<ALERTMANAGER_PORT\> | 告警管理 |
