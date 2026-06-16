# setup-redis — Redis 8.0 生产级部署

使用 Docker Compose 在本地或远程服务器上部署生产级 Redis 8.0，包含密码认证、AOF 持久化、内存策略和危险命令禁用配置。

## 简介

| 项目 | 内容 |
|------|------|
| 镜像版本 | redis:8.0-alpine |
| 容器名称 | tech-redis-{env} |
| 默认端口 | 6379 |
| 持久化目录（远程） | `/opt/tech-stack/redis-{env}/data` |
| 默认内存上限 | 512mb（allkeys-lru） |

## Prometheus 指标监控

内置 `redis_exporter v1.67.0` sidecar 容器，随 Redis 自动启动，暴露 `:9121/metrics` 端口。

**采集指标**：内存使用率、Key 驱逐速率、缓存命中率、连接数、每秒命令数。

**告警规则**：`setup-prometheus` 已预置 `RedisHighMemoryUsage`、`RedisHighKeyEviction` 告警，exporter 启动后自动生效。

## 目录结构

```
setup-redis/
├── SKILL.md                        # 路由指令（Claude AI 读取）
├── actions/
│   ├── start.md                    # 完整启动流程（含本地/远程两种模式）
│   ├── stop.md
│   ├── status.md
│   ├── verify.md
│   └── logs.md
├── references/
│   ├── docker-compose.yml          # 生产级配置
│   ├── .env.example                # 密码占位符模板
│   └── conf/
│       ├── redis.conf              # Redis 生产优化配置
│       └── users.acl               # ACL 权限规则（禁用危险命令）
├── README.md
└── install.sh
```

## 安装步骤

在 tech-stack-setup 仓库根目录下运行：

```bash
bash setup-redis/install.sh
```

脚本将 `setup-redis/` 全部内容复制到 `~/.claude/skills/setup-redis/`。

## 部署示例

### 密码认证

```
/setup-redis start --host <HOST> --user ubuntu --password mySSHpassword
```

### SSH Key 认证

```
/setup-redis start --host <HOST> --user ubuntu --key ~/.ssh/id_rsa
```

### 指定非标准 SSH 端口

```
/setup-redis start --host <HOST> --user ubuntu --key ~/.ssh/id_rsa --ssh-port 2222
```

## .env 配置说明

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `REDIS_PASSWORD` | 无（必填） | default 用户密码（管理运维），最少 16 位 |
| `REDIS_APP_USER` | app | 业务应用用户名 |
| `REDIS_APP_PASSWORD` | 无（必填） | 业务应用用户密码 |
| `REDIS_PORT` | 6379 | 宿主机映射端口 |
| `REDIS_MAX_MEMORY` | 512mb | Redis 最大内存限制 |
| `REDIS_EXPORTER_USER` | exporter | Prometheus 采集用户名 |
| `REDIS_EXPORTER_PASSWORD` | 无（必填） | Prometheus 采集用户密码 |

## 用户模型

通过 `aclfile`（`/data/users.acl`）管理 3 个用户：

| 用户 | 权限 | 用途 |
|------|------|------|
| `default` | `+@all`（全部） | 管理运维 |
| `app` | `+@all` 除 flushdb/flushall/shutdown/debug 等 | 业务应用连接 |
| `exporter` | 仅 ping/info/config 等只读 | Prometheus 采集 |

> Redis 8.0 将 `info`、`keys`、`config` 归入 `@dangerous` 组，业务应用必须使用 `app` 用户，不能使用 `default -@dangerous`。

## 生产注意事项

1. **统一配置管理**：所有可变配置（密码、端口、内存）均通过 `.env` 管理，`redis.conf` 仅包含静态配置
2. **业务应用用 app 用户**：`app` 用户拥有所有数据操作权限但禁用了破坏性命令（flushdb、shutdown 等）
3. **内存策略**：默认 `allkeys-lru`，适合纯缓存场景；若需持久化重要数据，改为 `volatile-lru` 或 `noeviction`
4. **AOF 持久化**：`appendfsync everysec` 模式在极端故障下最多丢失 1 秒数据，同时启用了 RDB 快照作为备份
5. **端口安全**：生产服务器建议通过防火墙限制 6379 端口访问范围，不要对公网开放
6. **禁止 rm -rf data/**：`data/` 包含 AOF/RDB 持久化数据和 `users.acl`，修改 ACL 只覆写 `data/users.acl` 然后重启
7. **内存监控**：当 `used_memory` 接近 `maxmemory` 时会触发 eviction，建议配置告警
