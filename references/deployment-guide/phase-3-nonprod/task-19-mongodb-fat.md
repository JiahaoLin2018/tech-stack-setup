# Task 19 — MongoDB FAT 部署

> 部署 FAT 环境 MongoDB（K3s 外部独立 Docker Compose）。对应 architecture-blueprint.md 第五部分阶段三。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS），hosts.lan 含 `mongodb-fat.renew.com` |
| 端口 | :27017（业务直连）/ :9216（mongodb_exporter） |

## 架构约束

- A 类环境级完全独立
- 启用 `security.authorization`（强制认证）
- WiredTiger Cache = 容器内存 50%
- exporter 用户仅 `clusterMonitor + read` 权限

## 关键配置

| 变量 | fat 值 |
|------|--------|
| `ENV` | `fat` |
| `MONGO_INITDB_ROOT_PASSWORD` | `<PASS>` |
| `MONGO_CACHE_SIZE_GB` | `1` |
| 容器内存 | 2g |

## 部署命令

```bash
/setup-mongodb start --host <MONGODB_FAT_IP> --env fat --user <USER> --password <PASS>
/setup-mongodb verify --host <MONGODB_FAT_IP> --env fat --user <USER> --password <PASS>
```

## 验证标准

- [ ] `mongosh "mongodb://appuser:<APP_PASS>@mongodb-fat.renew.com:27017/admin"` 可连接
- [ ] `curl http://mongodb-fat.renew.com:9216/metrics` 返回 mongodb_exporter 指标
- [ ] 容器名 `tech-mongodb-fat` + `tech-mongodb-exporter-fat` 全部 Running

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 2g | 1-2 核 | 100 GB |

## 并行说明

与同环境其他中间件完全并行。

## 后续步骤

- 密码记录到 `env/mongodb-fat.md`
- task-30 通过 `mongodb-fat.renew.com:9216` 抓取 metrics
