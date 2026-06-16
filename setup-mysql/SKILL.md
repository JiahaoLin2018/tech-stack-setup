---
name: setup-mysql
description: 使用 Docker Compose 部署和管理 MySQL 8.4，支持多环境独立实例（dev/sit/fat/uat/prod）。当用户提到部署 MySQL、启动数据库、配置 MySQL 容器、检查数据库状态等需求时，务必使用此 skill。支持 start / stop / status / verify / logs 操作。
argument-hint: "[start|stop|status|verify|logs] [--env <env>] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]"
disable-model-invocation: true
---

> **路径约定**：本文档中 `<skill_dir>` 指 SKILL.md 所在目录（安装后为 `~/.claude/skills/setup-mysql`）。

# setup-mysql — MySQL 8.4 生产级部署

使用 Docker Compose 在远程服务器上部署、管理和验证业务 MySQL 8.4 容器，每环境（dev/sit/fat/uat/prod）独立部署一套实例。

> **职责边界**：本 skill 仅负责**业务 MySQL** × 5 套，每个环境一套独立物理实例。Apollo 配置中心专用 MySQL（`ApolloPortalDB` / `ApolloConfigDB_*`）由 `setup-apollo` 内置管理，与本 skill 无关。

## 文档职责说明

| 文档 | 读者 | 职责 |
|------|------|------|
| **SKILL.md** | Claude Code（AI） | 技能执行指令 — 定义 frontmatter、action 路由、执行流程 |
| **README.md** | 人（开发者/用户） | 入门指引文档 — 安装教程、配置说明、功能介绍、使用示例 |

## 配置

- 配置文件模板位于 `<skill_dir>/references/`
- 远程部署目录：`/opt/tech-stack/mysql-{env}/`（env 由 `--env` 参数决定，如 `/opt/tech-stack/mysql-dev/`）

## 用法

```
/setup-mysql [action] [选项]

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
| `start` | 部署并启动 MySQL 容器（默认 action） |
| `stop` | 停止并移除 MySQL 容器 |
| `status` | 查看 MySQL 容器运行状态 |
| `verify` | 验证 MySQL 服务连通性和健康状态 |
| `logs` | 查看 MySQL 容器日志 |

## 执行流程

1. 解析参数：提取 ENV（默认 dev，校验合法值）、ACTION（默认 start）、HOST（默认 localhost）、SSH_USER（默认 root）、SSH_PORT（默认 22）、AUTH（password 或 key）
   - ENV 合法值：`dev|sit|fat|uat|prod`；传入其他值立即报错退出
2. 读取 `<skill_dir>/actions/<action>.md` 按步骤执行

## 重要说明

- 生产环境必须修改 .env 中所有 `CHANGE_ME_*` 密码
- Exporter 密码三处必须保持一致：`.env` 的 `MYSQL_EXPORTER_PASSWORD`、`conf/exporter.my.cnf` 的 `password=`、`init/01_create_app_user.sql` 的 `IDENTIFIED BY`，否则 exporter 无法连接（详见 [pitfalls.md](references/pitfalls.md)）

## 多环境部署说明

每个环境（dev/sit/fat/uat/prod）部署**完全独立的物理实例**，通过 `--env` 参数区分。

| 配置项 | dev | sit | fat | uat | prod |
|--------|-----|-----|-----|-----|------|
| 直连域名 | `mysql-dev.renew.com:3306` | `mysql-sit.renew.com:3306` | `mysql-fat.renew.com:3306` | `mysql-uat.renew.com:3306` | `mysql-prod.renew.com:3306` |
| 部署目录 | `/opt/tech-stack/mysql-dev/` | `/opt/tech-stack/mysql-sit/` | `/opt/tech-stack/mysql-fat/` | `/opt/tech-stack/mysql-uat/` | `/opt/tech-stack/mysql-prod/` |
| 容器名 | `tech-mysql-dev` | `tech-mysql-sit` | `tech-mysql-fat` | `tech-mysql-uat` | `tech-mysql-prod` |
| 内存配额 | 1g | 1g | 2g | 2g | 4g |

**业务 DB 命名建议**（业务层约定）：每个独立实例内，业务数据库以环境为前缀命名（如 `dev_demo`、`prod_order`），便于识别。Spring Boot 应用通过 Apollo 配置中心读取 `mysql.host=mysql-{env}.renew.com` 与业务 DB 名连接对应实例。

## 踩坑记录规则

> 部署过程中遇到的问题，按以下流程处理：
> 1. **修复模板**：将 fix 写入 `references/` 配置文件或 `actions/start.md` 流程步骤，确保下次部署自动生效
> 2. **记录 pitfalls.md**：在 `references/pitfalls.md` 追加条目，注明问题现象、根因和修复方案
