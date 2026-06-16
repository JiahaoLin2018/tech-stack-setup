# 踩坑记录 — setup-redis

> 所有部署中遇到的问题记录于此。问题已在 actions/ 流程中修复，本文件仅作历史存档和排障参考。

## [2026-03-17] ACL 文件注释导致 Redis 启动失败

- **现象**：Redis 8.0 启动报错 `should start with user keyword followed by the username`
- **根因**：Redis 8.0 的 ACL 文件解析器不再允许注释行（`#` 开头）
- **修复**：已在 `references/conf/users.acl` 中移除所有注释行，仅保留 ACL 规则

## [2026-03-17] ACL 文件覆盖 --requirepass 导致认证失效

- **现象**：所有认证请求返回 `WRONGPASS`，即使密码正确
- **根因**：`redis.conf` 中配置了 `aclfile`，ACL 文件中定义了无密码的 default 用户。Redis 8.0 中 ACL 文件优先级高于 `--requirepass`，导致密码设置被覆盖
- **修复**：认证方式统一改为 `aclfile`（存放在 `/data/users.acl` 可写卷中），移除 `--requirepass` 参数

## [2026-03-18] data 目录误删导致数据丢失

- **现象**：修复 ACL 问题时误执行 `rm -rf data/*`，导致 Redis 持久化数据（AOF + RDB）全部丢失
- **根因**：`data/` 目录同时包含 `users.acl`、`appendonlydir/`（AOF）和 `dump.rdb`（RDB），不能整目录删除
- **修复**：已在 SKILL.md 注意事项中强调禁止 `rm -rf data/*`。修改 ACL 的正确方式：只覆写 `data/users.acl` 然后重启

## ACL 密码注入与运行时持久化

`references/conf/users.acl` 是密码占位符模板（`__REDIS_PASSWORD__` / `__REDIS_APP_PASSWORD__` / `__REDIS_EXPORTER_PASSWORD__`），不是 Redis 直接加载的文件。`actions/start.md` 第 7 步在首次部署时执行 `sed` 替换 `.env` 中的实际密码后，写入可写卷 `data/users.acl`，由 `aclfile /data/users.acl` 指令加载。

后续 ACL 变更（新增用户、修改权限、轮换密码）必须通过 `ACL SETUSER` + `ACL SAVE` 在线执行，由 Redis 自身持久化回 `data/users.acl`。**不要直接编辑 `data/users.acl`**——Redis 启动后会持续写回该文件，手动编辑会被覆盖。

`conf/users.acl` 模板仅作首次部署的密码注入入口，部署目录中的 `data/users.acl` 才是运行时权威。

## ACL 危险命令禁用清单（生产）

业务用户 `app` 已在 `conf/users.acl` 中显式排除以下命令，覆盖蓝图第四部分的 Redis 安全加固要求：

| 类别 | 命令 | 风险 |
|------|------|------|
| 数据销毁 | `flushdb`、`flushall` | 一键清库 |
| 进程控制 | `shutdown`、`debug` | 直接关停或影响调试 |
| 复制拓扑 | `replicaof`、`slaveof`、`migrate` | 重定向数据流 |
| 模块加载 | `module` | 加载任意 .so 提权 |
| 持久化触发 | `save`、`bgsave`、`bgrewriteaof`、`restore` | 阻塞 / 覆盖数据 |
| 数据库切换 | `swapdb` | 跨 DB 数据互换 |
| 管理命令组 | `-@admin` | 一次性排除 CONFIG/CLIENT KILL/ACL 等高危管理操作 |

`exporter` 用户走最小权限白名单（`-@all` + 显式 `+ping +info +select` 等），无需再单独禁用。

`default` 用户保留 `+@all` 仅用于运维管理，业务连接禁止使用。

## 三处密码一致性校验

Exporter 密码涉及三个位置：

1. `.env` 的 `REDIS_EXPORTER_PASSWORD`
2. `data/users.acl` 中 `user exporter` 行的 `>密码` 字段
3. `docker-compose.yml` 的 `redis-exporter` 容器 `REDIS_PASSWORD` 环境变量（来源于 `.env`）

位置 1 和 3 同源（Compose 直接读 `.env`），位置 2 在首次部署时由 `actions/start.md` 第 7 步从 `.env` 渲染生成；后续轮换密码必须同时更新 `.env` 和通过 `ACL SETUSER exporter >新密码` 在线变更，否则 Prometheus 抓取会因认证失败而中断。`actions/start.md` 第 8 步内置启动前校验，发现不一致直接退出。
