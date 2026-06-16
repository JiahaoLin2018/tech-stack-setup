# 踩坑记录 — setup-apollo

> 所有部署中遇到的问题记录于此。问题已在 actions/ 流程中修复，本文件仅作历史存档和排障参考。

## [2026-04-08] Admin Service 内存限制不足导致 OOM 频繁重启（严重）

- **现象**：Admin Service 容器频繁重启（`docker ps` 显示 `Up X seconds`），`dmesg` 显示 `Memory cgroup out of memory`，Portal 报 `Admin servers are unresponsive`
- **根因**：Admin Service 默认内存限制 `384MiB`，JVM 堆内存 `-Xmx384m` 加上非堆内存（Metaspace、线程栈等）后实际需求约 430-460MiB，超出限制导致 OOM
- **修复**：已在 references/docker-compose.nonprod.yml 和 docker-compose.prod.yml 中将 Admin Service 内存限制从 384m 增加到 512m，JVM 堆内存初始值调整为 `-Xms256m`
- **注意**：Config Service 512m 通常足够，PRO 环境已设为 768m；监控内存使用：`docker stats --no-stream | grep apollo`

## [2026-04-08] Portal 配置中中文乱码

- **现象**：PortalDB 中 `organizations` 等含中文的配置显示为乱码（如 `技术部` 显示为 `æŠ€æœ¯éƒ¨`）
- **根因**：MySQL 客户端连接时字符集设置不正确，UTF-8 编码被错误解释
- **修复**：已在 actions/start.md 步骤 11 中使用 `--default-character-set=utf8mb4` 参数。备选方案：使用 HEX 编码直接写入正确的 UTF-8 字节，或通过 Portal UI 操作

## [2026-04-08] Portal 配置更新后需重启容器才能生效

- **现象**：修改 PortalDB 中 `apollo.portal.meta.servers` 后，Portal 仍使用旧配置
- **根因**：Portal 启动时缓存数据库配置，`apollo.portal.meta.servers`、`apollo.portal.envs` 等核心配置不支持热加载
- **修复**：已在 actions/start.md 步骤 12 中在配置优化后自动重启 Portal

## [2026-04-08] Eureka 注册信息缓存导致连接失败

- **现象**：Portal 日志显示 `Connect to 172.19.0.X:8090 failed: Connection refused`，但实际容器 IP 已变化
- **根因**：Admin Service 重启后获得新的 Docker 内网 IP，但 Eureka 中仍缓存旧 IP
- **修复**：根源是 Admin OOM 导致频繁重启（已修复内存限制）。等待 Eureka 自动更新约 30-90 秒，或重启 Portal 强制刷新

## [2026-04-07] 数据库初始化 docker exec -i 静默失败

- **现象**：`docker exec -i apollo-db mysql ... < /tmp/apolloconfigdb.sql` 返回 0，无报错，但数据库为空（0 张表）
- **根因**：通过 paramiko `exec_command` 运行的命令，stdin 重定向 `< file` 无法将宿主机文件内容传给容器内的 mysql，mysql 收到空输入后立即退出
- **修复**：已在 actions/start.md 步骤 10 中改为两步操作——先 `docker cp` 将文件复制进容器，再 `docker exec bash -c "mysql < /tmp/file.sql"` 在容器内执行。**切勿改回 `docker exec -i` 形式**

## [2026-04-07] sed 替换模式遗漏导致新环境库为空壳

- **现象**：ApolloConfigDB_sit/fat/uat/prod 数据库存在但 0 张表，Config Service 报 `Unable to create requested service [JdbcEnvironment]` 反复重启
- **根因**：apolloconfigdb.sql 中数据库名有三种写法：① 带反引号 `` `ApolloConfigDB` ``、② 无反引号 `CREATE DATABASE IF NOT EXISTS ApolloConfigDB`、③ 混合大小写 `Use ApolloConfigDB;`。sed 只替换了第①种，②③未替换，所有表被错误导入到 dev 库
- **修复**：已在 actions/start.md 步骤 10 中使用多个 `-e` 参数覆盖全部写法，并在初始化后验证表数量

## [2026-04-07] FWS 不可用作独立环境名（Apollo 2.5.0 硬编码限制）

- **现象**：`apollo.portal.envs = dev,fws,fat,...` → Portal 看到两个 FAT 环境，FWS 消失
- **根因**：Apollo Portal 2.5.0 的 `Env.getWellFormName()` 方法将 `FWS` 强制映射到 `FAT`。同样 `PROD` → `PRO`
- **修复**：使用 `SIT`（System Integration Testing）替代 FWS。Portal 环境列表使用 `pro`（Apollo 内置名 PRO），容器/数据库后缀使用 `prod`

## [2026-04-03] 生产环境默认配置安全风险

- **现象**：Apollo 初始化后多项 ServerConfig 存在安全风险或环境不匹配
- **根因**：官方默认值不适合生产环境（`consumer.token.salt=someSalt`、`namespace.lock.switch=false` 等）
- **修复**：已在 actions/start.md 步骤 11 中自动从 .env 读取安全值并更新 PortalDB 和 ConfigDB

## [2026-03-18] 首次部署必须初始化数据库

- **现象**：Config Service 启动后报 `Unable to create requested service [JdbcEnvironment]` 并反复重启
- **根因**：Apollo 官方镜像不会自动创建 `ApolloConfigDB` 和 `ApolloPortalDB`，数据库不存在时服务无法启动
- **修复**：已在 actions/start.md 步骤 10 中自动检测并从 GitHub 下载官方 SQL 执行初始化

## [2026-03-18] eureka.service.url 默认 localhost 在容器内不通

- **现象**：Admin Service 无法注册到 Config Service 的 Eureka
- **根因**：初始化 SQL 在 `ApolloConfigDB_{env}.ServerConfig` 中写入 `eureka.service.url = http://localhost:8080/eureka/`，容器内 localhost 指向自身而非 Config Service
- **修复**：已在 actions/start.md 步骤 10 数据库初始化后自动将 eureka URL 修正为 `http://apollo-config-{env}:8080/eureka/`
