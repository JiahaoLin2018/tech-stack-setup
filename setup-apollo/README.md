# setup-apollo

使用 Docker Compose 部署和管理 Apollo 2.5.0 分布式配置中心。D 类合并部署：`--env nonprod` 一次拉起 10 容器（Apollo 专用 MySQL + Portal + dev/sit/fat/uat 各 Config/Admin），`--env prod` 一次拉起 3 容器（生产专用 MySQL + Config + Admin）。Apollo MySQL 内置管理，与业务 MySQL（setup-mysql）完全独立；非生产与生产 MySQL 物理隔离。

## 安装

```bash
bash install.sh
```

安装后即可在 Claude Code 中使用 `/setup-apollo` 命令。

## 前提条件

- 远程模式：SSH 可连接目标服务器；密码模式需本地安装 `sshpass`

## 服务组成

### nonprod 模式（10 容器）

| 容器名 | 镜像 | 宿主机端口 | 说明 |
|--------|------|-----------|------|
| tech-apollo-db | mysql:8.4 | 3307 | Apollo 专用 MySQL（5 Schema） |
| tech-apollo-portal | apolloconfig/apollo-portal:2.5.0 | 8070 | Portal UI（全局唯一） |
| tech-apollo-config-dev | apolloconfig/apollo-configservice:2.5.0 | 8601 | DEV Config Service |
| tech-apollo-admin-dev | apolloconfig/apollo-adminservice:2.5.0 | 8611 | DEV Admin Service |
| tech-apollo-config-sit | apolloconfig/apollo-configservice:2.5.0 | 8602 | SIT Config Service |
| tech-apollo-admin-sit | apolloconfig/apollo-adminservice:2.5.0 | 8612 | SIT Admin Service |
| tech-apollo-config-fat | apolloconfig/apollo-configservice:2.5.0 | 8603 | FAT Config Service |
| tech-apollo-admin-fat | apolloconfig/apollo-adminservice:2.5.0 | 8613 | FAT Admin Service |
| tech-apollo-config-uat | apolloconfig/apollo-configservice:2.5.0 | 8604 | UAT Config Service |
| tech-apollo-admin-uat | apolloconfig/apollo-adminservice:2.5.0 | 8614 | UAT Admin Service |

### prod 模式（3 容器）

| 容器名 | 镜像 | 宿主机端口 | 说明 |
|--------|------|-----------|------|
| tech-apollo-db | mysql:8.4 | 3307 | 生产专用 MySQL（独立实例） |
| tech-apollo-config-prod | apolloconfig/apollo-configservice:2.5.0 | 8605 | PROD Config Service |
| tech-apollo-admin-prod | apolloconfig/apollo-adminservice:2.5.0 | 8615 | PROD Admin Service |

## 支持的命令

| 命令 | 说明 |
|------|------|
| `/setup-apollo start` | 启动全部服务（含 DB 健康等待，最多 3 分钟） |
| `/setup-apollo stop` | 停止并移除所有容器 |
| `/setup-apollo status` | 查看所有容器状态及资源占用 |
| `/setup-apollo verify` | 逐步验证 DB、Config、Admin、Portal 可达性及 Eureka 注册 |
| `/setup-apollo logs` | 查看各容器日志 |

## 远程部署示例

```bash
# 使用密码部署到远程服务器
/setup-apollo start --host <HOST> --user deploy --password mypassword

# 使用 SSH 密钥部署
/setup-apollo start --host <HOST> --key ~/.ssh/id_rsa

# 查看远程服务状态
/setup-apollo status --host <HOST> --key ~/.ssh/id_rsa
```

## .env 配置说明

工作目录 `/opt/tech-stack/apollo-{nonprod|prod}/` 中的 `.env` 文件：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `APOLLO_DB_ROOT_PASSWORD` | `CHANGE_ME_*` | MySQL root 密码，生产必须修改，最少 16 字符 |
| `APOLLO_DB_PORT` | `3307` | MySQL 对外暴露端口（避免与本地 3306 冲突） |
| `APOLLO_ENVS` | `dev,sit,fat,uat,pro` | Portal 管理的环境列表（生产用 pro，Apollo 内置名 PRO） |
| `APOLLO_CONFIG_PORT_DEV` | `8601` | DEV Config Service 端口 |
| `APOLLO_CONFIG_PORT_SIT` | `8602` | SIT Config Service 端口 |
| `APOLLO_CONFIG_PORT_FAT` | `8603` | FAT Config Service 端口 |
| `APOLLO_CONFIG_PORT_UAT` | `8604` | UAT Config Service 端口 |
| `APOLLO_CONFIG_PORT_PROD` | `8605` | PRO Config Service 端口（容器后缀 prod） |
| `APOLLO_PORTAL_PORT` | `8070` | Portal UI 端口（与 infra-nginx 代理一致） |

## Spring Boot 集成

按部署环境选择对应 Config Service 端口：

```properties
# dev 环境
app.id=YOUR_APP_ID
apollo.meta=http://apollo-config-dev.renew.com

# fat 环境（CI/CD 默认）
app.id=YOUR_APP_ID
apollo.meta=http://apollo-config-fat.renew.com
```

或 `application.yml`：

```yaml
app:
  id: YOUR_APP_ID
apollo:
  meta: http://apollo-config-fat.renew.com  # fat 环境（apollo-config-{env}.renew.com）
  bootstrap:
    enabled: true
    namespaces: application
```

> **注意**：Config Service 通过 `apollo-config-{env}.renew.com` 域名访问，由 infra-nginx 代理转发到后端端口（8601-8605）。
> Portal Web UI 使用 `apollo.renew.com`，同样通过 infra-nginx 代理访问。

## 多环境配置（合并部署模式）

每个环境（dev/sit/fat/uat/prod）拥有独立的 Config Service + Admin Service，Portal 统一管理：

| 环境 | Spring Boot 接入地址 | Admin（仅 Portal 使用） |
|------|---------------------|----------------------|
| dev | http://apollo-config-dev.renew.com | :8611 |
| sit | http://apollo-config-sit.renew.com | :8612 |
| fat | http://apollo-config-fat.renew.com | :8613 |
| uat | http://apollo-config-uat.renew.com | :8614 |
| prod | http://apollo-config-prod.renew.com | :8615 |

## 目录结构

```
setup-apollo/
├── SKILL.md                      # AI 执行指令
├── actions/
│   ├── start.md                  # 启动流程（本地+远程，含分步健康等待）
│   ├── stop.md
│   ├── status.md
│   ├── verify.md
│   └── logs.md
├── references/
│   ├── docker-compose.nonprod.yml # nonprod 10 容器（MySQL+Portal+4×Config/Admin）
│   ├── docker-compose.prod.yml    # prod 3 容器（MySQL_prod+Config+Admin）
│   ├── pitfalls.md                # 踩坑记录
│   └── .env.example               # 环境变量模板
├── README.md
└── install.sh
```

## 注意事项

- Apollo 启动有严格依赖链：apollo-db → apollo-config → apollo-admin / apollo-portal，由 Docker Compose 自动管理启动顺序
- 首次启动 MySQL 初始化约 30-60 秒，所有服务就绪最多需 3-5 分钟
- 生产环境必须修改 `APOLLO_DB_ROOT_PASSWORD`，最少 16 字符
- 生产环境首次登录后应修改默认账号密码（默认 apollo / admin）
- 通过 infra-nginx 代理访问 Portal，域名：apollo.renew.com
- **生产环境必须优化默认配置**（步骤 11 自动执行）：
  - `consumer.token.salt`：默认值存在安全风险，已替换为随机盐值
  - `namespace.lock.switch`：开启命名空间锁，防止多人同时修改冲突
  - `configView.memberOnly.envs`：所有环境仅项目成员可查看配置

## 部署模式（合并部署：nonprod 10 容器 / prod 3 容器）

每个环境（dev/sit/fat/uat/prod）拥有独立的 Config Service + Admin Service 实例。

### nonprod 模式

```
apollo-db (MySQL:3307) ← 非生产共用 MySQL，独立 schema
  ├── ApolloPortalDB（Portal 库）
  ├── ApolloConfigDB_dev
  ├── ApolloConfigDB_sit
  ├── ApolloConfigDB_fat
  └── ApolloConfigDB_uat

apollo-portal:8070（全局唯一 Portal）
  ├── DEV → apollo-config-dev:8080 (Docker 内网)
  ├── SIT → apollo-config-sit:8080 (Docker 内网)
  ├── FAT → apollo-config-fat:8080 (Docker 内网)
  ├── UAT → apollo-config-uat:8080 (Docker 内网)
  └── PRO → apollo-config-prod.renew.com (跨网段，infra-nginx 代理)
```

### prod 模式（独立部署于生产网段）

```
apollo-db (MySQL:3307) ← 生产专用 MySQL，与非生产完全隔离
  └── ApolloConfigDB_prod

apollo-config-prod:8605 → apollo-admin-prod:8615
```

> **注意**：
> - nonprod 与 prod 使用**独立的 MySQL 实例**，物理隔离
> - Portal 仅在 nonprod 模式部署，通过 `PRO_META` 域名跨网段管理生产配置
> - **8601-8605 是宿主机暴露的内部端口，infra-nginx 通过这些端口代理各环境的 Config Service**
> - Spring Boot 客户端通过 `apollo-config-{env}.renew.com`（infra-nginx 代理）访问
> - Portal 通过 Docker 内网（容器名:8080）连接各环境 Config Service，PRO 环境通过域名跨网段访问
