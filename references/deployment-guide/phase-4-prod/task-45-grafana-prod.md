# Task 45 — Grafana 生产部署

> 部署生产统一可视化看板。对应 architecture-blueprint.md 第五部分阶段四 4-9。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-42/43/44（Tempo/Loki/Prometheus prod 数据源）+ task-02（infra-nginx 跨网段反代） |
| 端口 | :3000 |

## 架构约束

- B 类，生产物理孤岛独立 1 套
- 自身不写 hosts.lan
- Web UI 域名 `grafana-prod-ui.renew.com` 由全局 infra-nginx **跨网段**反代到生产 :3000
- 生产建议 LDAP / OAuth 认证

## 关键配置

| 变量 | prod 值 |
|------|--------|
| `ENV` | `prod` |
| `GRAFANA_ADMIN_PASSWORD` | `<PASS>` |
| `GRAFANA_ROOT_URL` | `http://grafana-prod-ui.renew.com` |
| `PROMETHEUS_HOST` | `prometheus-prod.renew.com` |
| `TEMPO_HOST` | `tempo-prod.renew.com` |
| `LOKI_HOST` | `loki-prod.renew.com` |
| Loki 租户头 | `X-Scope-OrgID: prod`（task-43 开启 `LOKI_AUTH_ENABLED=true` 后必需；skill 模板未注入，部署后**手动**在 Grafana UI 编辑 Loki 数据源添加 Custom HTTP Header） |
| 容器内存 | 512m |

## 部署命令

```bash
/setup-grafana start --host <GRAFANA_PROD_IP> --env prod --user <USER> --password <PASS>
/setup-grafana verify --host <GRAFANA_PROD_IP> --env prod --user <USER> --password <PASS>
```

## 验证标准

- [ ] `http://grafana-prod-ui.renew.com` 可登录
- [ ] 三个数据源就绪（Prometheus / Tempo / Loki）Test 全绿（Loki 数据源需先在 UI 手动添加 `X-Scope-OrgID: prod` 自定义头后 Test 才会变绿）
- [ ] 生产 Dashboard 数据正常

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 512 MB | 0.5-1 核 | 20 GB |

## 并行说明

必须在 task-44（Prometheus prod）就绪后部署。

## 注意事项

- `GRAFANA_ROOT_URL` 必须设为反代域名
- 修改默认 admin 密码（密码记录到 `env/grafana-prod.md`）
- 生产强烈建议接入 LDAP / OAuth
- Loki 数据源由 provisioning 模板生成（`editable: false`），如需添加 `X-Scope-OrgID: prod` 租户头，部署后手动 SSH 到主机编辑 `/opt/tech-stack/grafana-prod/conf/grafana/provisioning/datasources/datasources.yml`，在 Loki 数据源 `jsonData` 增补 `httpHeaderName1: 'X-Scope-OrgID'` 和 `secureJsonData.httpHeaderValue1: 'prod'`，并 `docker compose restart` 容器

## 后续步骤

- 导入生产 Dashboard
- 验证跨网段 UI 访问（开发者从内网通过 infra-nginx 反代访问）
