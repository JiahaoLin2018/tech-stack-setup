# setup-mongodb — MongoDB 8.0 生产级部署

使用 Docker Compose 在本地或远程服务器上部署生产级 MongoDB 8.0，包含认证加固、WiredTiger 调优和慢操作日志配置。

## 简介

| 项目 | 内容 |
|------|------|
| 镜像版本 | mongo:8.0（可通过 .env 配置） |
| 容器名称 | tech-mongodb-{env} |
| 默认端口 | 27017 |
| 持久化目录（远程） | `/opt/tech-stack/mongodb-{env}/data` |

## Prometheus 指标监控

内置 `mongodb_exporter 0.43.1`（Percona）sidecar 容器，随 MongoDB 自动启动，暴露 `:9216/metrics` 端口。

**采集指标**：连接数、WiredTiger 缓存使用率、操作计数（CRUD）、复制集延迟、全局锁等待。

**告警规则**：`setup-prometheus` 已预置 `MongodbConnectionsHigh`、`MongodbCacheHighUsage`、`MongodbReplicationLag` 告警，exporter 启动后自动生效。

## 目录结构

```
setup-mongodb/
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
│   │   └── mongod.conf             # MongoDB 生产优化配置
│   └── init/
│       └── 01_create_app_user.js   # 初始化应用用户脚本
├── README.md
└── install.sh
```

## 安装步骤

在 tech-stack-setup 仓库根目录下运行：

```bash
bash setup-mongodb/install.sh
```

脚本将 `setup-mongodb/` 全部内容复制到 `~/.claude/skills/setup-mongodb/`。

## 部署示例

### SSH Key 认证（推荐）

```
/setup-mongodb start --host <HOST> --user ubuntu --key ~/.ssh/id_rsa
```

### 密码认证

> **安全警告**：`--password` 方式传递 SSH 密码会留在 shell history 中，生产环境强烈建议使用 `--key` 方式。

```
/setup-mongodb start --host <HOST> --user ubuntu --password mySSHpassword
```

### 指定非标准 SSH 端口

```
/setup-mongodb start --host <HOST> --user ubuntu --key ~/.ssh/id_rsa --ssh-port 2222
```

## .env 配置说明

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MONGO_IMAGE` | mongo:8.0 | MongoDB 镜像及版本 |
| `ENV` | dev | 部署环境（dev\|sit\|fat\|uat\|prod），决定容器名 tech-mongodb-{env} 和部署目录 |
| `MONGO_PORT` | 27017 | 宿主机映射端口 |
| `MONGO_INITDB_ROOT_USERNAME` | admin | 管理员用户名 |
| `MONGO_INITDB_ROOT_PASSWORD` | 无（必填） | 管理员密码，最少 16 位 |
| `MONGO_APP_DATABASE` | appdb | 应用数据库名 |
| `MONGO_APP_USER` | appuser | 应用用户名 |
| `MONGO_APP_PASSWORD` | 无（必填） | 应用用户密码，最少 16 位 |
| `MONGO_MEMORY_LIMIT` | 2g | 容器内存上限 |
| `MONGO_MEMORY_RESERVATION` | 512m | 容器内存预留 |
| `MONGO_CACHE_SIZE_GB` | 1 | WiredTiger 缓存大小（GB），建议为 MONGO_MEMORY_LIMIT 的 50% |
| `MONGO_MAX_CONNECTIONS` | 500 | 最大连接数 |
| `MONGO_SLOW_OP_THRESHOLD_MS` | 200 | 慢操作阈值（毫秒） |
| `MONGO_LOG_MAX_SIZE` | 100m | 单个日志文件大小上限 |
| `MONGO_LOG_MAX_FILE` | 5 | 日志文件保留数量 |

## 生产注意事项

1. **密码强度**：所有密码必须替换 `CHANGE_ME_*` 占位符，建议使用 16 位以上随机字符串
2. **内存调优**：`MONGO_CACHE_SIZE_GB` 应设为 `MONGO_MEMORY_LIMIT` 的 50%（如 4g 容器设 2）；生产大内存服务器按需调大 `MONGO_MEMORY_LIMIT` 和 `MONGO_CACHE_SIZE_GB`
3. **认证安全**：已启用 `security.authorization`，所有连接必须携带用户名密码
4. **初始化失败保护**：`MONGO_APP_PASSWORD` 未设置时初始化脚本将抛出异常，容器启动失败，便于第一时间发现配置遗漏
5. **应用用户权限**：`init/01_create_app_user.js` 赋予应用用户 readWrite + dbAdmin 权限，生产建议按最小权限原则调整
6. **端口安全**：`mongod.conf` 中 `bindIp: 0.0.0.0` 绑定所有接口以支持跨服务通信；生产服务器务必通过防火墙限制 `MONGO_PORT` 的访问来源
7. **磁盘监控**：MongoDB 数据目录增长较快（特别是 journal 和 oplog），建议配置磁盘告警阈值
8. **备份策略**：建议使用 `mongodump` 定期备份，或配置副本集实现高可用
