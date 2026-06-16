# Task 09 — MongoDB Dev 部署

> 部署 Dev 环境 MongoDB（K3s 外部独立 Docker Compose）。对应 architecture-blueprint.md 第五部分阶段三 3-3。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS）已完成，hosts.lan 含 `mongodb-dev.renew.com` |
| 端口 | :27017（业务直连）/ :9216（mongodb_exporter） |

## 架构约束

- A 类环境级完全独立
- 启用 `security.authorization`（强制认证）
- WiredTiger Cache = 容器内存 50%
- exporter 用户仅 `clusterMonitor + read` 权限

## 关键配置

| 变量 | Dev 值 |
|------|--------|
| `ENV` | `dev` |
| `MONGO_INITDB_ROOT_PASSWORD` | `<PASS>` |
| `MONGO_APP_PASSWORD` | 业务用户密码 |
| `MONGO_EXPORTER_PASSWORD` | exporter 用户密码 |
| `MONGO_CACHE_SIZE_GB` | `0.5` |
| 容器内存 | 1g |

## 部署命令

```bash
/setup-mongodb start --host <MONGODB_DEV_IP> --env dev --user <USER> --password <PASS>
/setup-mongodb verify --host <MONGODB_DEV_IP> --env dev --user <USER> --password <PASS>
```

## 验证标准

- [ ] `mongosh "mongodb://appuser:<APP_PASS>@mongodb-dev.renew.com:27017/admin"` 可连接
- [ ] `curl http://mongodb-dev.renew.com:9216/metrics` 返回 mongodb_exporter 指标
- [ ] 容器名 `tech-mongodb-dev` + `tech-mongodb-exporter-dev` 全部 Running

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 1 GB | 1 核 | 100 GB |

## 并行说明

与 Dev 其他中间件（task-07/08/10/11）完全并行。

## 后续步骤

- 密码记录到 `env/mongodb-dev.md`
- task-30 通过 `mongodb-dev.renew.com:9216` 抓取 metrics
