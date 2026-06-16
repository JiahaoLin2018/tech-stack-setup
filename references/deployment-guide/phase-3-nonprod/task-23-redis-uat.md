# Task 23 — Redis UAT 部署

> 部署 UAT 环境 Redis（K3s 外部独立 Docker Compose）。对应 architecture-blueprint.md 第五部分阶段三。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS），hosts.lan 含 `redis-uat.renew.com` |
| 端口 | :6379（业务直连）/ :9121（redis_exporter） |

## 架构约束

- A 类环境级完全独立
- ACL 三类用户：default（禁用） / app / exporter
- AOF + RDB 持久化默认启用

## 关键配置

| 变量 | uat 值 |
|------|--------|
| `ENV` | `uat` |
| `REDIS_APP_PASSWORD` | 业务用户密码 |
| `REDIS_MAX_MEMORY` | `1g` |
| 容器内存 | 2g |

## 部署命令

```bash
/setup-redis start --host <REDIS_UAT_IP> --env uat --user <USER> --password <PASS>
/setup-redis verify --host <REDIS_UAT_IP> --env uat --user <USER> --password <PASS>
```

## 验证标准

- [ ] `redis-cli -h redis-uat.renew.com -p 6379 --user app --pass <APP_PASS> ping` 返回 PONG
- [ ] `curl http://redis-uat.renew.com:9121/metrics` 返回 redis_exporter 指标
- [ ] 容器名 `tech-redis-uat` + `tech-redis-exporter-uat` 全部 Running

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 2g | 1-2 核 | 50 GB |

## 并行说明

与同环境其他中间件完全并行。

## 后续步骤

- 密码记录到 `env/redis-uat.md`
- task-30 通过 `redis-uat.renew.com:9121` 抓取 metrics
