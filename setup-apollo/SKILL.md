---
name: setup-apollo
description: 使用 Docker Compose 部署和管理 Apollo 2.5.0 配置中心（含内置专用 MySQL）。支持合并部署模式：--env nonprod 一次拉起 10 个容器（MySQL+Portal+4环境Config/Admin），--env prod 一次拉起 3 个容器（MySQL_prod+Config_prod+Admin_prod），生产与非生产 MySQL 完全物理隔离。当开发者需要启动、停止、查看状态、验证或查看日志 Apollo 服务时触发此 skill。
argument-hint: "[start|stop|status|verify|logs] [--env nonprod|prod] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]"
disable-model-invocation: true
---

> **路径约定**：本文档中 `<skill_dir>` 指 SKILL.md 所在目录（安装后为 `~/.claude/skills/setup-apollo`）。

# setup-apollo — Apollo 配置中心部署

提供 Apollo 2.5.0 配置中心的完整生命周期管理，支持合并部署模式和远程服务器 SSH 部署。

## 文档职责说明

| 文档 | 读者 | 职责 |
|------|------|------|
| **SKILL.md** | Claude Code（AI） | 技能执行指令 — 定义 frontmatter、action 路由、执行流程 |
| **README.md** | 人（开发者/用户） | 入门指引文档 — 安装教程、配置说明、功能介绍、使用示例 |

## 配置

- 配置文件模板位于 `<skill_dir>/references/`
- 远程部署目录：`/opt/tech-stack/apollo-{env}/`（env = nonprod 或 prod）

> **配置渲染例外说明**：本服务不使用 `.tpl` 模板 + `envsubst` 渲染机制。原因：Apollo 为 Java 应用（Portal/Config/Admin），配置参数通过 `docker-compose.yml` 的环境变量注入（如 `spring_datasource_url`、`apollo_portal_meta_servers`），无需模板渲染。

## 用法

```
/setup-apollo [action] [选项]

action: start（默认）| stop | status | verify | logs

选项:
  --env <env>        部署模式（nonprod|prod，默认: nonprod；传错报错退出）
  --host <ip>        部署目标 IP（默认: localhost）
  --user <user>      SSH 用户名（默认: root，仅远程）
  --password <pass>  SSH 密码（仅远程，与 --key 二选一）
  --key <path>       SSH 私钥路径（仅远程，与 --password 二选一）
  --ssh-port <n>     SSH 端口（默认: 22）
```

## `--env` 参数契约（D 类 — Apollo 特殊合并部署）

| 参数 | 容器数 | 部署目录 | 内容 |
|------|--------|---------|------|
| `--env nonprod`（默认） | 10 | /opt/tech-stack/apollo-nonprod/ | Apollo 专用 MySQL + Portal(:8070) + dev/sit/fat/uat 各 Config+Admin |
| `--env prod` | 3 | /opt/tech-stack/apollo-prod/ | 生产专用 MySQL + Config(:8605) + Admin(:8615) |
| 传入其他值 | — | — | 立即报错退出 |

## Actions

| Action | 说明 |
|--------|------|
| `start` | 部署并启动 Apollo 容器（默认 action） |
| `stop` | 停止并移除 Apollo 容器 |
| `status` | 查看 Apollo 各组件容器运行状态 |
| `verify` | 验证 Apollo 服务连通性和健康状态 |
| `logs` | 查看 Apollo 容器日志 |

## 执行流程

1. 解析参数：提取 ENV（默认 nonprod，传入无效值立即报错退出）、ACTION（默认 start）、HOST（默认 localhost）、SSH_USER（默认 root）、SSH_PORT（默认 22）、AUTH（password 或 key）
2. 推导：`DEPLOY_DIR=/opt/tech-stack/apollo-${ENV}`、compose 文件选择 `docker-compose.${ENV}.yml`
3. 读取 `<skill_dir>/actions/<action>.md` 按步骤执行

## SSH_CMD 约定

action 文件中的 `SSH_CMD "..."` 是伪命令，执行时根据认证方式展开：

```bash
# 密码模式
sshpass -p "${SSH_PASSWORD}" ssh -o StrictHostKeyChecking=no -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} "..."

# 密钥模式
ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} "..."
```

## 容器架构

### nonprod 模式（10 容器）

| 容器名 | 端口 | 说明 |
|--------|------|------|
| tech-apollo-db | 3307 | Apollo 专用 MySQL（5 Schema：PortalDB + dev/sit/fat/uat） |
| tech-apollo-portal | 8070 | 统一管理 UI（全局唯一，仅 nonprod 部署） |
| tech-apollo-config-dev | 8601 | Dev Config Service |
| tech-apollo-admin-dev | 8611 | Dev Admin Service |
| tech-apollo-config-sit | 8602 | SIT Config Service |
| tech-apollo-admin-sit | 8612 | SIT Admin Service |
| tech-apollo-config-fat | 8603 | FAT Config Service |
| tech-apollo-admin-fat | 8613 | FAT Admin Service |
| tech-apollo-config-uat | 8604 | UAT Config Service |
| tech-apollo-admin-uat | 8614 | UAT Admin Service |

> Portal 中 PRO 环境配置为空占位，阶段四 `setup-apollo --env prod` 后再接入。

### prod 模式（3 容器）

| 容器名 | 端口 | 说明 |
|--------|------|------|
| tech-apollo-db | 3307 | 生产专用 MySQL（1 Schema：ApolloConfigDB_prod），与非生产 MySQL 完全物理隔离 |
| tech-apollo-config-prod | 8605 | 生产 Config Service |
| tech-apollo-admin-prod | 8615 | 生产 Admin Service |

## 环境差异配置表

| 配置项 | DEV | SIT | FAT | UAT | PROD |
|--------|-----|-----|-----|-----|------|
| Config Service 端口 | 8601 | 8602 | 8603 | 8604 | 8605 |
| Admin Service 端口 | 8611 | 8612 | 8613 | 8614 | 8615 |
| 数据库 Schema | ApolloConfigDB_dev | ApolloConfigDB_sit | ApolloConfigDB_fat | ApolloConfigDB_uat | ApolloConfigDB_prod |
| Apollo 内置环境名 | DEV | SIT | FAT | UAT | **PRO** |
| Meta Server 域名 | apollo-config-dev.renew.com | apollo-config-sit.renew.com | apollo-config-fat.renew.com | apollo-config-uat.renew.com | apollo-config-prod.renew.com |
| 部署阶段 | nonprod（阶段二） | nonprod（阶段二） | nonprod（阶段二） | nonprod（阶段二） | prod（阶段四） |

## Spring Boot 接入

| 环境 | `apollo.meta` | 说明 |
|------|---------------|------|
| dev | `http://apollo-config-dev.renew.com` | infra-nginx 代理 :80 → :8601 |
| sit | `http://apollo-config-sit.renew.com` | infra-nginx 代理 :80 → :8602 |
| fat | `http://apollo-config-fat.renew.com` | infra-nginx 代理 :80 → :8603 |
| uat | `http://apollo-config-uat.renew.com` | infra-nginx 代理 :80 → :8604 |
| prod | `http://apollo-config-prod.renew.com` | infra-nginx 代理 :80 → :8605 |

> `apollo-config-{env}.renew.com` 由泛解析→infra-nginx 代理，不写入 hosts.lan，无需带端口。

## 重要说明

- Apollo MySQL 由本 Skill 内置管理，**不依赖** setup-mysql，与业务 MySQL 完全独立
- 启动有严格依赖链：apollo-db → apollo-config-{env}（并行）→ apollo-admin-{env}（各自串行）/ apollo-portal
- 首次启动最多等待 5-8 分钟（MySQL 初始化 + Java 服务启动）
- Portal 默认密码 apollo/admin，首次登录后务必修改
- `docker compose up -d` 可能因 healthcheck 链等待超时（SSH 连接断开），服务实际后台继续启动，稍后用 `docker compose up -d --no-recreate` 触发剩余服务

## 环境名硬编码限制（Apollo 2.5.0）

Apollo 2.5.0 硬编码映射：`FWS` → `FAT`、`PROD` → `PRO`。因此：
- 使用 `SIT` 替代 FWS
- 生产环境在 Portal 配置中使用 `PRO`，容器/数据库后缀使用 `prod`

## 踩坑记录规则

> 部署过程中遇到的问题，按以下流程处理：
> 1. **修复模板**：将 fix 写入 `references/` 配置文件或 `actions/start.md` 流程步骤，确保下次部署自动生效
> 2. **记录 pitfalls.md**：在 `references/pitfalls.md` 追加说明（仅记录无法自动化的操作风险和使用指引）
> 3. **同步 start.md**：若涉及新增步骤，更新 `actions/start.md` 并调整步骤编号

> 历史踩坑记录及解决方案详见 [pitfalls.md](references/pitfalls.md)，部署中遇到的新问题也请记录到该文件。
