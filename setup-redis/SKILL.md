---
name: setup-redis
description: 使用 Docker Compose 部署和管理 Redis 8.0，支持多环境独立实例（dev/sit/fat/uat/prod）。当用户提到部署 Redis、启动缓存服务、配置 Redis 容器、检查 Redis 状态等需求时，务必使用此 skill。支持 start / stop / status / verify / logs 操作。
argument-hint: "[start|stop|status|verify|logs] [--env <env>] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]"
disable-model-invocation: true
---

> **路径约定**：本文档中 `<skill_dir>` 指 SKILL.md 所在目录（安装后为 `~/.claude/skills/setup-redis`）。

# setup-redis — Redis 8.0 生产级部署

帮助开发者使用 Docker Compose 在远程服务器上部署、管理和验证 Redis 8.0 容器（生产级配置，含密码认证、AOF 持久化、危险命令禁用）。

## 文档职责说明

| 文档 | 读者 | 职责 |
|------|------|------|
| **SKILL.md** | Claude Code（AI） | 技能执行指令 — 定义 frontmatter、action 路由、执行流程 |
| **README.md** | 人（开发者/用户） | 入门指引文档 — 安装教程、配置说明、功能介绍、使用示例 |

## 配置

- 配置文件模板位于 `<skill_dir>/references/`
- 远程部署目录：`/opt/tech-stack/redis-{env}/`（env 由 `--env` 参数决定，如 `/opt/tech-stack/redis-dev/`）

> **配置注入路径**：动态参数（`maxmemory`、端口、内存上限）由 `.env` → Docker Compose 环境变量 → `docker-compose.yml` 的 `command` 注入；静态参数（持久化策略、淘汰策略等）固定写在 `conf/redis.conf`。ACL 用户与密码由 `actions/start.md` 在首次部署时从 `.env` 渲染 `conf/users.acl` 模板（占位符 `__REDIS_*_PASSWORD__`）写入可写卷 `data/users.acl`，运行时通过 `ACL SETUSER` + `ACL SAVE` 在线变更并由 Redis 自身持久化。

## 用法

```
/setup-redis [action] [选项]

action: start（默认）| stop | status | verify | logs

选项:
  --env <env>        部署环境（dev|sit|fat|uat|prod，默认: dev）
  --host <ip>        部署目标 IP（默认: localhost）
  --user <user>      SSH 用户名（默认: root，仅远程）
  --password <pass>  SSH 密码（仅远程，与 --key 二选一）
  --key <path>       SSH 私钥路径（仅远程，与 --password 二选一）
  --ssh-port <n>     SSH 端口（默认: 22）
```

> **--env 契约（A 类）**：取值必须为 `dev|sit|fat|uat|prod`，默认 `dev`，传入非法值立即报错退出。每次调用部署一个独立实例，5 个环境各部署一次共 5 套。

## Actions

| Action | 说明 |
|--------|------|
| `start` | 部署并启动 Redis 容器（默认 action） |
| `stop` | 停止并移除 Redis 容器 |
| `status` | 查看 Redis 容器运行状态 |
| `verify` | 验证 Redis 服务连通性和健康状态 |
| `logs` | 查看 Redis 容器日志 |

## 执行流程

1. 解析参数：提取 ENV（默认 dev，校验合法值）、ACTION（默认 start）、HOST（默认 localhost）、SSH_USER（默认 root）、SSH_PORT（默认 22）、AUTH（password 或 key）
   - ENV 合法值：`dev|sit|fat|uat|prod`；传入其他值立即报错退出
2. 读取 `<skill_dir>/actions/<action>.md` 按步骤执行

## 重要说明

- 生产环境必须修改 .env 中所有 `CHANGE_ME_*` 密码
- 所有可变配置（密码、端口、内存）统一通过 `.env` 管理，`redis.conf` 仅包含静态配置

## 注意事项

### 业务应用必须使用 `app` 用户
Redis 8.0 将 `info`、`keys`、`config` 归入 `@dangerous` 组。`default` 用户虽有全部权限但仅供管理运维。业务应用应使用 `app` 用户（`+@all` 减去破坏性命令），可正常执行 `INFO` 等健康检查命令。

### 绝对不能 `rm -rf data/*`
`data/` 目录包含 AOF/RDB 持久化数据和 `users.acl`。修改 ACL 时只覆写 `data/users.acl` 然后重启，不能删除整个目录。

### ACL 用户模型
3 个用户定义在 `data/users.acl` 中，密码字段在首次部署时由 `.env` 注入，Redis `ACL SAVE` 后改为 SHA256 hash 形式：

| 用户 | 权限 | 密码来源 | 用途 |
|------|------|---------|------|
| `default` | `+@all` | `.env` `REDIS_PASSWORD` | 管理运维 |
| `app` | `+@all -@admin -flushdb -flushall -shutdown -debug -replicaof -slaveof -migrate -module -save -bgsave -bgrewriteaof -restore -swapdb` | `.env` `REDIS_APP_PASSWORD` | 业务应用 |
| `exporter` | `-@all` 显式白名单（`+ping +info +select +dbsize +type +scan +slowlog +latency +config +client +cluster +memory +command +time`） | `.env` `REDIS_EXPORTER_PASSWORD` | Prometheus 采集 |

> 历史踩坑记录及解决方案详见 [pitfalls.md](references/pitfalls.md)，部署中遇到的新问题也请记录到该文件。

## 多环境部署说明

每个环境（dev/sit/fat/uat/prod）部署**完全独立的物理实例**，通过 `--env` 参数区分。

| 配置项 | dev | sit | fat | uat | prod |
|--------|-----|-----|-----|-----|------|
| 直连域名 | `redis-dev.renew.com:6379` | `redis-sit.renew.com:6379` | `redis-fat.renew.com:6379` | `redis-uat.renew.com:6379` | `redis-prod.renew.com:6379` |
| 部署目录 | `/opt/tech-stack/redis-dev/` | `/opt/tech-stack/redis-sit/` | `/opt/tech-stack/redis-fat/` | `/opt/tech-stack/redis-uat/` | `/opt/tech-stack/redis-prod/` |
| 容器名 | `tech-redis-dev` | `tech-redis-sit` | `tech-redis-fat` | `tech-redis-uat` | `tech-redis-prod` |
| 内存配额 | 512mb | 512mb | 1g | 1g | 2g |

**Apollo 配置**：应用通过 `redis.host=redis-{env}.renew.com`、`redis.database=0` 连接对应实例（每个实例独立，DB 0 即可）。

## 踩坑记录规则

> 部署过程中遇到的问题，按以下流程处理：
> 1. **修复模板**：将 fix 写入 `references/` 配置文件或 `actions/start.md` 流程步骤，确保下次部署自动生效
> 2. **记录 pitfalls.md**：在 `references/pitfalls.md` 追加条目，注明问题现象、根因和修复方案
