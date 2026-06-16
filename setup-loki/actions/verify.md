# action: verify — 验证 Loki 服务

## 参数解析

> 继承主调用的 `--env` 参数，`ENV` = nonprod 或 prod。

## 步骤

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  echo '=== 验证 Loki Ready ==='
  curl -sf http://localhost:3100/ready && echo 'Loki 正常' || echo 'Loki 未就绪'

  echo ''
  echo '=== 验证 Loki Metrics ==='
  curl -sf http://localhost:3100/metrics > /dev/null 2>&1 && echo 'Metrics 端点正常' || echo 'Metrics 端点未就绪'

  echo ''
  echo '=== 验证 Loki Labels API ==='
  curl -sf http://localhost:3100/loki/api/v1/labels && echo '' && echo 'Labels API 正常' || echo 'Labels API 未就绪'
"
```

---

## LogQL 查询示例

验证日志推送后，可在 Grafana Explore 中使用 LogQL 查询：

| 查询 | 说明 |
|------|------|
| `{app="my-service"}` | 查看某应用的所有日志 |
| `{app="my-service"} \|= "ERROR"` | 按关键字过滤 |
| `{app="my-service"} \| json \| status >= 500` | JSON 解析 + 条件过滤 |
| `rate({app="my-service"} \|= "ERROR" [5m])` | 错误速率（每 5 分钟） |
| `{app="my-service"} \| logfmt \| duration > 1s` | logfmt 解析 + 慢请求过滤 |
| `topk(10, sum by(app) (rate({job="varlogs"} [1h])))` | 日志量 Top 10 应用 |

---

## 访问地址汇总

| 端点 | 地址 | 说明 |
|------|------|------|
| API 根路径 | http://\<HOST\>:3100 | Loki HTTP API |
| Ready 检查 | http://\<HOST\>:3100/ready | 健康检查端点 |
| Metrics | http://\<HOST\>:3100/metrics | Prometheus 格式指标 |
| Labels | http://\<HOST\>:3100/loki/api/v1/labels | 已索引标签列表 |
| Push | http://\<HOST\>:3100/loki/api/v1/push | 日志推送端点 |
