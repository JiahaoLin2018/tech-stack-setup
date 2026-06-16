# 踩坑记录 — setup-mysql

> 部署过程中遇到的问题记录于此。问题已在 actions/ 与 references/ 中固化解决，本文件仅作排障参考与决策档案。

## [2026-03-17] mysqld_exporter v0.16.0 连接方式

- **现象**：exporter 启动即崩溃，报错 `failed to validate config: no user specified in section or parent` / `Error parsing host config: no configuration found`
- **根因**：mysqld_exporter v0.16.0 移除了 `DATA_SOURCE_NAME` 环境变量支持，必须使用 `.my.cnf` 配置文件或命令行参数
- **当前实现**：`references/docker-compose.yml` 通过 `--config.my-cnf=/etc/.my.cnf` 命令行参数挂载 `conf/exporter.my.cnf`
- **决策原因**：相比命令行参数（密码以明文出现在 docker inspect），`.my.cnf` 文件挂载只读卷更安全且语义清晰

## [2026-03-17] exporter 用户与 root@localhost 限制的关系

- **现象**：exporter 容器启动后报 `Access denied for user 'root'@'172.21.0.3' (using password: NO)`
- **根因**：初始化脚本 `01_create_app_user.sql` 限制 root 仅 localhost 登录，但 exporter 从独立容器（不同 IP）连接 MySQL
- **当前实现**：`references/init/01_create_app_user.sql` 创建 `exporter@'%'` 专用监控用户，仅授予 `PROCESS`、`REPLICATION CLIENT`、`SELECT` 只读权限（蓝图 §安全加固基线要求）

## Exporter 密码三处一致性

`MYSQL_EXPORTER_PASSWORD` 出现于三个位置，必须保持完全一致，否则 exporter 容器启动失败：

| 位置 | 文件 | 字段 |
|---|---|---|
| 环境变量 | `.env` | `MYSQL_EXPORTER_PASSWORD=` |
| 客户端配置 | `conf/exporter.my.cnf` | `password=` |
| 用户初始化 | `init/01_create_app_user.sql` | `IDENTIFIED BY '...'` |

`actions/start.md` 步骤 6 强制要求 `.env` 替换全部 `CHANGE_ME_*` 后才允许 start，未做自动化交叉校验时由人工核对。

## 业务 MySQL 与 Apollo MySQL 的边界

setup-mysql 仅负责业务 MySQL × 5 套（dev/sit/fat/uat/prod 各一）。Apollo 配置中心使用的 `ApolloPortalDB` / `ApolloConfigDB_*` 由 `setup-apollo` 内置的专用 MySQL 管理，与本 skill 无关，部署时不要在业务 MySQL 中创建 Apollo Schema。
