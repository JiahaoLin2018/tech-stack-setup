# Redis 8.0 — 部署报告

| 项目   | 值                                                          |
| ---- | ---------------------------------------------------------- |
| 部署日期 | 2026-03-17                                                 |
| 更新日期 | 2026-03-18                                                 |
| 目标机器 | 192.168.82.93 (Server A)                                   |
| 部署目录 | `/opt/tech-stack/redis/`                                   |
| 容器名称 | tech-redis / tech-redis-exporter                           |
| 镜像   | redis:8.0-alpine / oliver006/redis_exporter:v1.67.0-alpine |
| 版本   | Redis 8.0.6                                                |

## 端口

| 端口   | 用途                             |
| ---- | ------------------------------ |
| 6379 | Redis 服务                       |
| 9121 | Prometheus 指标 (redis-exporter) |

## 账号密码

| 用户       | 密码                          | 权限                          | 用途           |
| -------- | --------------------------- | --------------------------- | ------------ |
| default  | RdsDefault_O49ZILEN5knL6gKk | +@all（全部）                    | 管理运维         |
| app      | RdsApp_5znpdyotLZgUeQZh    | +@all 除 flushdb/shutdown 等   | 业务应用（推荐）     |
| exporter | RdsExp_3kH4COWYOx6qLaIl     | 仅 ping/info/config 等只读       | Prometheus 采集 |

## 连接方式

| 方式          | 地址                                                                                                                 |
| ----------- | ------------------------------------------------------------------------------------------------------------------ |
| Redis URI (app) | `redis://app:RdsApp_5znpdyotLZgUeQZh@redis.renew.com:6379` |
| redis-cli (app) | `redis-cli -h redis.renew.com --user app -a RdsApp_5znpdyotLZgUeQZh` |
| Spring Boot | `spring.data.redis.host=redis.renew.com`<br>`spring.data.redis.port=6379`<br>`spring.data.redis.username=app`<br>`spring.data.redis.password=RdsApp_5znpdyotLZgUeQZh` |
| Exporter    | http://redis.renew.com:9121/metrics |

## 配置

| 参数               | 值                    |
| ---------------- | -------------------- |
| maxmemory        | 512mb                |
| maxmemory-policy | allkeys-lru          |
| 持久化              | AOF (everysec) + RDB |
| ACL 持久化          | `/data/users.acl`    |

## 备注

- 使用 aclfile（`/data/users.acl`）管理 3 个用户，密码以 SHA256 hash 存储
- `default` 用户拥有全部权限，仅供管理运维使用
- `app` 用户供业务应用连接，禁用 flushdb/flushall/shutdown/debug 等破坏性命令
- `exporter` 用户仅授权监控类只读命令
- Redis 8.0 将 `info`、`keys`、`config` 归入 `@dangerous` 组，业务应用必须使用 `app` 用户而非 `default -@dangerous`
