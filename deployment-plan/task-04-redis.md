# Task 04 — 部署 Redis

- **状态**: ✅ 完成
- **目标机器**: 192.168.82.93
- **Skill**: setup-redis
- **前置依赖**: Task 02 (DNS)
- **内存预算**: 512M

## 执行内容

1. 执行 `/setup-redis start` 部署 Redis 8.0
2. 修改默认密码
3. 配置 maxmemory 限制为 256M-512M
4. 验证连接

## Skill 命令

```bash
/setup-redis start --host 192.168.82.93 --user root --password foxconn.88
/setup-redis verify --host 192.168.82.93 --user root --password foxconn.88
```

## 内存调优要点

- `maxmemory 512mb`（严格限制，避免内存膨胀）
- Redis Exporter 随 Redis 一起部署（:9121）

## 验证标准

- [ ] Redis 容器运行中
- [ ] 可通过 `redis.renew.com:6379` 连接
- [ ] Redis Exporter `:9121` 可访问

## 完成记录

- 开始时间:
- 完成时间:
- 备注:
