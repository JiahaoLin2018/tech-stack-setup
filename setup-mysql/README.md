# setup-mysql — MySQL 8.4 生产级部署

使用 Docker Compose 在本地或远程服务器上部署生产级 MySQL 8.4，包含安全加固、性能调优和慢查询日志配置。

## 简介

| 项目 | 内容 |
|------|------|
| 镜像版本 | mysql:8.4 |
| 容器名称 | tech-mysql-{env}（如 tech-mysql-dev） |
| 默认端口 | 3306 |
| 持久化目录（远程） | `/opt/tech-stack/mysql-{env}/data` |
| 多环境支持 | 5 套独立实例：dev/sit/fat/uat/prod |

## Prometheus 指标监控

内置 `mysqld_exporter v0.16.0` sidecar 容器，随 MySQL 自动启动，暴露 `:9104/metrics` 端点。

**连接方式**：exporter 通过挂载 `conf/exporter.my.cnf` 使用专用 `exporter` 用户连接 MySQL。该用户由 `init/01_create_app_user.sql` 自动创建，仅拥有 `PROCESS`、`REPLICATION CLIENT`、`SELECT` 权限。

**采集指标**：连接数/连接池使用率、慢查询速率、InnoDB 缓冲池命中率、QPS/TPS、锁等待。

**抓取契约**：`setup-prometheus` 在 `prometheus.nonprod.yml` 中按 `mysql-{dev|sit|fat|uat}` 配置 4 个 job、在 `prometheus.prod.yml` 中配置 1 个 `mysql-prod` job，每个 job 通过 `relabel_configs` 注入 `env={env}` 标签。

**告警规则**：`setup-prometheus` 已预置 `MysqlConnectionsHigh`、`MysqlSlowQueries` 告警，exporter 启动后自动生效。

## 目录结构

```
setup-mysql/
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
│   ├── conf/
│   │   ├── my.cnf                  # MySQL 生产优化配置
│   │   └── exporter.my.cnf        # mysqld-exporter 连接配置
│   └── init/
│       └── 01_create_app_user.sql  # 初始化脚本（安全加固 + exporter 用户）
├── README.md
└── install.sh
```

## 安装步骤

在 tech-stack-setup 仓库根目录下运行：

```bash
bash setup-mysql/install.sh
```

脚本将 `setup-mysql/` 全部内容复制到 `~/.claude/skills/setup-mysql/`。

## 部署示例

### 部署 Dev 环境 MySQL

```
/setup-mysql start --env dev --host <HOST> --user ubuntu --key ~/.ssh/id_rsa
```

### 部署 Prod 环境 MySQL

```
/setup-mysql start --env prod --host <HOST> --user ubuntu --key ~/.ssh/id_rsa
```

### 查看 SIT 环境状态

```
/setup-mysql status --env sit --host <HOST> --user ubuntu --key ~/.ssh/id_rsa
```

## .env 配置说明

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MYSQL_ROOT_PASSWORD` | 无（必填） | root 密码，最少 16 位 |
| `MYSQL_APP_USER` | appuser | 应用用户名 |
| `MYSQL_APP_PASSWORD` | 无（必填） | 应用用户密码，最少 16 位 |
| `MYSQL_DATABASE` | appdb | 初始创建的数据库名 |
| `MYSQL_PORT` | 3306 | 宿主机映射端口 |
| `TZ` | Asia/Shanghai | 容器时区 |
| `MYSQL_MEMORY_LIMIT` | 2g | 容器内存上限 |
| `MYSQL_MEMORY_RESERVATION` | 512m | 容器内存预留 |
| `MYSQLD_EXPORTER_PORT` | 9104 | Exporter 端口 |
| `MYSQL_EXPORTER_PASSWORD` | 无（必填） | Exporter 用户密码，需与 `conf/exporter.my.cnf` 和 `init/01_create_app_user.sql` 一致 |

## 部署后密码同步

部署时需要保证三处密码一致：

| 位置 | 文件 | 说明 |
|------|------|------|
| exporter 用户创建 | `init/01_create_app_user.sql` | `IDENTIFIED BY '<密码>'` |
| exporter 连接配置 | `conf/exporter.my.cnf` | `password=<密码>` |
| 环境变量模板 | `.env` | `MYSQL_EXPORTER_PASSWORD=<密码>` |

> 修改密码时三处必须同步替换 `CHANGE_ME_EXPORTER_PASSWORD`，否则 exporter 无法连接 MySQL。

## 生产注意事项

1. **密码强度**：所有密码必须替换 `CHANGE_ME_*` 占位符，建议使用 16 位以上随机字符串
2. **内存调整**：`MYSQL_INNODB_BUFFER_POOL` 应根据实际服务器内存调整（建议总内存的 70%）
3. **binlog 备份**：已启用 ROW 格式 binlog，建议配合定期备份策略使用
4. **root 访问限制**：`init/01_create_app_user.sql` 已限制 root 仅本地登录，生产建议只使用应用用户
5. **端口安全**：生产服务器建议通过防火墙限制 3306 端口访问范围，或通过内网连接
6. **磁盘监控**：MySQL 数据目录增长较快，建议配置磁盘告警阈值

## 安全加固

- root 账号限制仅 localhost 登录（由 `init/01_create_app_user.sql` 配置）
- `exporter` 监控用户仅拥有 `PROCESS`、`REPLICATION CLIENT`、`SELECT` 三项只读权限
- 应用用户 `appuser` 通过 `MYSQL_USER` / `MYSQL_PASSWORD` 由镜像入口创建，权限范围 `*.*`（建议生产按业务库收敛）
- `local-infile=0`、`symbolic-links=0` 默认启用（见 `conf/my.cnf`）
- 生产环境通过宿主机防火墙限制 3306 仅对应用网段开放
