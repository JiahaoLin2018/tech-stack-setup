---
name: setup-mongodb
description: 使用 Docker Compose 部署和管理 MongoDB 8.0，支持多环境独立实例（dev/sit/fat/uat/prod）。当用户提到部署 MongoDB、启动文档数据库、配置 MongoDB 容器、检查 MongoDB 状态等需求时，务必使用此 skill。支持 start / stop / status / verify / logs 操作。
argument-hint: "[start|stop|status|verify|logs] [--env <env>] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]"
disable-model-invocation: true
---

> **路径约定**：本文档中 `<skill_dir>` 指 SKILL.md 所在目录（安装后为 `~/.claude/skills/setup-mongodb`）。

# setup-mongodb — MongoDB 8.0 生产级部署

帮助开发者使用 Docker Compose 在远程服务器上部署、管理和验证 MongoDB 8.0 容器（生产级配置，含认证、应用用户初始化、WiredTiger 调优，所有关键参数通过 .env 统一管理）。

## 文档职责说明

| 文档 | 读者 | 职责 |
|------|------|------|
| **SKILL.md** | Claude Code（AI） | 技能执行指令 — 定义 frontmatter、action 路由、执行流程 |
| **README.md** | 人（开发者/用户） | 入门指引文档 — 安装教程、配置说明、功能介绍、使用示例 |

## 配置

- 配置文件模板位于 `<skill_dir>/references/`
- 远程部署目录：`/opt/tech-stack/mongodb-{env}/`（env 由 `--env` 参数决定，如 `/opt/tech-stack/mongodb-dev/`）

## 用法

```
/setup-mongodb [action] [选项]

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
| `start` | 部署并启动 MongoDB 容器（默认 action） |
| `stop` | 停止并移除 MongoDB 容器 |
| `status` | 查看 MongoDB 容器运行状态 |
| `verify` | 验证 MongoDB 服务连通性和健康状态 |
| `logs` | 查看 MongoDB 容器日志 |

## 执行流程

1. 解析参数：提取 ENV（默认 dev，校验合法值）、ACTION（默认 start）、HOST（默认 localhost）、SSH_USER（默认 root）、SSH_PORT（默认 22）、AUTH（password 或 key）
   - ENV 合法值：`dev|sit|fat|uat|prod`；传入其他值立即报错退出
2. 读取 `<skill_dir>/actions/<action>.md` 按步骤执行

## 重要说明

- 生产环境必须修改 .env 中所有 `CHANGE_ME_*` 密码

## 注意事项

### 认证启动顺序
`references/conf/mongod.conf` 中已启用 `security.authorization: enabled`。MongoDB 容器首次启动时会先执行 `docker-entrypoint-initdb.d/` 下的初始化脚本创建用户，再启用认证。若 `init/01_create_app_user.js` 执行失败（如 `MONGO_APP_PASSWORD` 未设置），容器会启动失败。

### exporter 密码必须一致
`.env`（`MONGO_EXPORTER_PASSWORD`）与 `init/01_create_app_user.js` 中创建的 exporter 用户密码必须相同，否则 exporter 无法连接。

> 历史踩坑记录及解决方案详见 [pitfalls.md](references/pitfalls.md)，部署中遇到的新问题也请记录到该文件。

## 多环境部署说明

每个环境（dev/sit/fat/uat/prod）部署**完全独立的物理实例**，通过 `--env` 参数区分。

| 配置项 | dev | sit | fat | uat | prod |
|--------|-----|-----|-----|-----|------|
| 直连域名 | `mongodb-dev.renew.com:27017` | `mongodb-sit.renew.com:27017` | `mongodb-fat.renew.com:27017` | `mongodb-uat.renew.com:27017` | `mongodb-prod.renew.com:27017` |
| 部署目录 | `/opt/tech-stack/mongodb-dev/` | `/opt/tech-stack/mongodb-sit/` | `/opt/tech-stack/mongodb-fat/` | `/opt/tech-stack/mongodb-uat/` | `/opt/tech-stack/mongodb-prod/` |
| 容器名 | `tech-mongodb-dev` | `tech-mongodb-sit` | `tech-mongodb-fat` | `tech-mongodb-uat` | `tech-mongodb-prod` |
| 内存配额 | 1g | 1g | 2g | 2g | 4g |

**Business DB 命名建议**（业务层约定）：每个独立实例内，业务数据库建议以环境为前缀命名（如 `dev_demo`、`prod_order`），便于识别。

**Apollo 配置**：应用通过 `mongo.host=mongodb-{env}.renew.com`、`mongo.db.name={env}_xxx` 连接对应实例。

## 踩坑记录规则

> 部署过程中遇到的问题，按以下流程处理：
> 1. **修复模板**：将 fix 写入 `references/` 配置文件或 `actions/start.md` 流程步骤，确保下次部署自动生效
> 2. **记录 pitfalls.md**：在 `references/pitfalls.md` 追加条目，注明问题现象、根因和修复方案
