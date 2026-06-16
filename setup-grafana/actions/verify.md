# action: verify — 验证 Grafana 服务

## 参数解析

> 继承主调用的 `--env` 参数，`ENV` = nonprod 或 prod。

## 步骤

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  echo '=== 验证 Grafana ==='
  GRAFANA_PASS=\$(grep '^GRAFANA_ADMIN_PASSWORD=' /opt/tech-stack/grafana-${ENV}/.env | cut -d= -f2)
  curl -sf -u \"admin:\${GRAFANA_PASS}\" http://localhost:3000/api/health && echo 'Grafana 正常' || echo 'Grafana 未就绪'
"
```

---

## 验证数据源连通性

```bash
echo ""
echo "=== 验证 Prometheus 数据源 ==="
GRAFANA_PASS=$(grep '^GRAFANA_ADMIN_PASSWORD=' /opt/tech-stack/grafana-${ENV}/.env | cut -d= -f2)
curl -sf -u "admin:${GRAFANA_PASS}" http://localhost:3000/api/datasources/name/Prometheus \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Prometheus 数据源: {d[\"type\"]} → {d[\"url\"]}')" \
  2>/dev/null || echo "Prometheus 数据源未配置（需部署 setup-prometheus 后生效）"

echo ""
echo "=== 验证 Tempo 数据源 ==="
curl -sf -u "admin:${GRAFANA_PASS}" http://localhost:3000/api/datasources/name/Tempo \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Tempo 数据源: {d[\"type\"]} → {d[\"url\"]}')" \
  2>/dev/null || echo "Tempo 数据源未配置（需部署 setup-tempo 后生效）"

echo ""
echo "=== 验证 Loki 数据源 ==="
curl -sf -u "admin:${GRAFANA_PASS}" http://localhost:3000/api/datasources/name/Loki \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Loki 数据源: {d[\"type\"]} → {d[\"url\"]}')" \
  2>/dev/null || echo "Loki 数据源未配置（需部署 setup-loki 后生效）"
```

---

## 推荐 Dashboard 导入说明

在 Grafana UI 中：Dashboards -> New -> Import -> 输入 Dashboard ID -> Load

| Dashboard | ID | 说明 |
|-----------|-----|------|
| JVM (Micrometer) | 4701 | JVM 堆内存、GC、线程、类加载等核心 JVM 指标 |
| Spring Boot 统计 | 12900 | HTTP 请求量、响应时间、错误率、Actuator 指标 |
| MySQL Overview | 7362 | MySQL 连接数、查询速率、锁等待、缓冲池 |
| Redis Dashboard | 11835 | Redis 内存、命中率、连接数、命令统计 |

导入时 Data Source 选择 `Prometheus`。

> **Tempo + Loki 集成**：Grafana 已预配置 Tempo 和 Loki 数据源。部署 `setup-tempo` 和 `setup-loki` 后，可在 Grafana 的 Explore 面板中使用 TraceQL 查询链路、LogQL 查询日志，并支持 Trace ↔ Log 双向跳转。

---

## Spring Boot 可观测性验证

Grafana 透明支持 Spring Boot 两种 OTel 接入方案：

| 方案 | 版本要求 | 验证方式 |
|------|---------|---------|
| 方案 A (Bridge) | SB 3.x + JDK 17+ | Metrics: `/actuator/prometheus` → Prometheus → Grafana |
| 方案 B (Agent) | SB 2.x 或 JDK < 17 | 同上，数据格式统一 |

验证步骤：

1. **Metrics**：在 Grafana Explore 中查询 `http_server_requests_seconds_count{env="<env>"}`
2. **Traces**：在 Explore → Tempo 中查询 `{resource.deployment.environment="<env>"}`
3. **Logs**：在 Explore → Loki 中查询 `{deployment_environment="<env>"}`
4. **跳转验证**：从 Trace 详情页点击 "Logs for this span"，确认跳转正常

> 详细集成架构见 README.md Spring Boot 可观测性集成章节。

---

## 访问地址汇总

| 服务 | 地址 | 说明 |
|------|------|------|
| Grafana | http://\<HOST\>:3000 | 可视化 Dashboard（admin / \<GRAFANA_ADMIN_PASSWORD\>） |
