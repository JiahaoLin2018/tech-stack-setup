# Task 08 — Redis Dev 部署

> 部署 Dev 环境 Redis（K3s 外部独立 Docker Compose）。对应 architecture-blueprint.md 第五部分阶段三 3-2。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS）已完成，hosts.lan 含 `redis-dev.renew.com` |
| 端口 | :6379（业务直连）/ :9121（redis_exporter） |

## 架构约束

- A 类环境级完全独立
- ACL 三类用户：`default`（禁用） / `app`（业务用） / `exporter`（监控只读）
- ACL 规则文件禁用 `CONFIG` / `DEBUG` / `FLUSHALL` 等危险命令

## 关键配置

| 变量 | Dev 值 |
|------|--------|
| `ENV` | `dev` |
| `REDIS_PASSWORD` | `<PASS>`（仅本机使用） |
| `REDIS_APP_PASSWORD` | 业务用户密码 |
| `REDIS_EXPORTER_PASSWORD` | exporter 用户密码 |
| `REDIS_MAX_MEMORY` | `512mb` |
| 容器内存 | 1g |

## 部署命令

```bash
/setup-redis start --host <REDIS_DEV_IP> --env dev --user <USER> --password <PASS>
/setup-redis verify --host <REDIS_DEV_IP> --env dev --user <USER> --password <PASS>
```

## 验证标准

- [ ] `redis-cli -h redis-dev.renew.com -p 6379 --user app --pass <APP_PASS> ping` 返回 PONG
- [ ] `curl http://redis-dev.renew.com:9121/metrics` 返回 redis_exporter 指标
- [ ] 容器名 `tech-redis-dev` + `tech-redis-exporter-dev` 全部 Running

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 1 GB | 1 核 | 50 GB |

## 并行说明

与 Dev 其他中间件（task-07/09/10/11）完全并行。

## 注意事项

- AOF + RDB 持久化默认启用
- `default` 用户必须禁用，业务通过 `app` 用户访问
- maxmemory 约为容器内存 50%

## 后续步骤

- 密码记录到 `env/redis-dev.md`
- task-30 通过 `redis-dev.renew.com:9121` 抓取 metrics
