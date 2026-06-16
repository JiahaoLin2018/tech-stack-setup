# 踩坑记录 — setup-mongodb

> 所有部署中遇到的问题记录于此。问题已在 actions/ 流程中修复，本文件仅作历史存档和排障参考。

## [2026-03-17] MongoDB 8.0 移除 journal.enabled 配置项

- **现象**：mongod 启动时报错 `Unrecognized option: storage.journal.enabled` 并反复重启
- **根因**：MongoDB 8.0 移除了 `storage.journal.enabled` 配置选项，日志功能改为强制启用
- **修复**：已在 `references/conf/mongod.conf` 中移除 `journal.enabled: true` 行

## [2026-03-18] exporter 改用专用监控用户

- **现象**：mongodb-exporter 使用 admin root 用户连接，权限过大存在安全风险
- **根因**：初始版本未创建专用 exporter 用户
- **修复**：已在 `references/init/01_create_app_user.js` 中新增 `exporter` 用户，仅授予 `clusterMonitor`（指标采集）+ `read` on `local`（oplog 读取）权限；`references/docker-compose.yml` 中 `MONGODB_URI` 改用 exporter 用户

## 认证启用与首次初始化的依赖顺序

- **机制说明**：`mongod.conf` 中已开启 `security.authorization: enabled`，但 MongoDB 在**仅且只在数据目录为空的首次启动**时，会绕过认证执行 `docker-entrypoint-initdb.d/` 下的脚本，用以创建 root / app / exporter 三个用户。脚本执行完毕后，后续的所有连接（包括重启）都强制走认证。
- **触发条件**：只要 `./data/` 已经存在并包含 WiredTiger 文件，MongoDB 启动时**不再执行**初始化脚本。这意味着在已运行实例上修改 `01_create_app_user.js` 后简单 `restart` **不会**生效；如需重新生成用户，必须停容器、清空 `./data/`、再重启。
- **常见症状**：
  - 首次启动若 `MONGO_APP_PASSWORD` 未设置，初始化脚本主动 `throw new Error`，容器随之启动失败 — 这是预期保护，便于第一时间发现配置遗漏。
  - 首次启动后修改 `.env` 中的 `MONGO_EXPORTER_PASSWORD`，但未重置 `./data/` → exporter 抓取持续 401，因为数据库里 exporter 用户的密码是首次启动时写入的旧值。
- **排障路径**：`docker logs tech-mongodb-${ENV}` 中找 `MongoServerError: Authentication failed` 提示，往往就是 .env 与 init 历史值不同步导致。

## [2026-03-19] mongodb_exporter 健康检查不能用 CMD-SHELL

- **现象**：在 `docker-compose.yml` 中将 `tech-mongodb-exporter-${ENV}` 的 healthcheck 写成 `CMD-SHELL`，容器持续 unhealthy
- **根因**：`percona/mongodb_exporter` 是基于 `scratch` 的最小化镜像，无 `/bin/sh`、无 `wget`、无 `curl`
- **修复**：healthcheck 改为 `CMD ["/mongodb_exporter", "--version"]`，仅检查二进制可执行
