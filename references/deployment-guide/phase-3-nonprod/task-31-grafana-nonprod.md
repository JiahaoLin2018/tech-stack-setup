# Task 31 — Grafana 非生产部署

> 部署非生产统一可视化看板（K3s 外部独立 Docker Compose）。对应 architecture-blueprint.md 第五部分阶段三 3-7。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-28/29/30（Tempo/Loki/Prometheus 数据源）+ task-02（infra-nginx，反代 UI 域名） |
| 端口 | :3000（HTTP） |

## 架构约束

- B 类域级共用
- 自身不写 hosts.lan（不作为数据端点）
- Web UI 域名 `grafana-nonprod-ui.renew.com` 走泛解析→infra-nginx 反代到 :3000
- 模板 `$env` 变量贯通 PromQL/LogQL/TraceQL 三向跳转，实现 Trace↔Log↔Metrics 联动

## 关键配置

| 变量 | nonprod 值 |
|------|----------|
| `ENV` | `nonprod` |
| `GRAFANA_ADMIN_PASSWORD` | `<PASS>` |
| `GRAFANA_ROOT_URL` | `http://grafana-nonprod-ui.renew.com` |
| `PROMETHEUS_HOST` | `prometheus-nonprod.renew.com` |
| `TEMPO_HOST` | `tempo-nonprod.renew.com` |
| `LOKI_HOST` | `loki-nonprod.renew.com` |
| 容器内存 | 512m |

## 部署命令

```bash
/setup-grafana start --host <GRAFANA_NONPROD_IP> --env nonprod --user <USER> --password <PASS>
/setup-grafana verify --host <GRAFANA_NONPROD_IP> --env nonprod --user <USER> --password <PASS>
```

## 验证标准

- [ ] `http://grafana-nonprod-ui.renew.com` 可登录（admin / 自定义密码）
- [ ] 三个数据源就绪：Prometheus / Tempo / Loki（Configuration → Data sources，Test 全绿）
- [ ] 模板 `$env` 变量可切换 dev/sit/fat/uat
- [ ] 至少一个 Dashboard 可视化指标 / 日志 / 链路

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 512 MB | 0.5-1 核 | 20 GB |

## 并行说明

必须在 task-30（Prometheus）就绪后部署。

## 注意事项

- `GRAFANA_ROOT_URL` 影响重定向和 OAuth 回调，必须设为反代域名
- 首次登录后必须修改 admin 密码（密码记录到 `env/grafana-nonprod.md`）
- 生产建议 LDAP / OAuth 认证（task-45）

## 后续步骤

- 导入预置 Dashboard（中间件指标 / Spring Boot / OTel Collector）
- task-32（OTel Collector nonprod）部署后，验证 Grafana 可查询完整链路追踪
