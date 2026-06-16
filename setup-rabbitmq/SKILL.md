---
name: setup-rabbitmq
description: 使用 Docker Compose 部署和管理 RabbitMQ 4.0，支持多环境独立实例（dev/sit/fat/uat/prod），含生产级配置、Management UI 和 Prometheus 指标暴露。当用户提到部署 RabbitMQ、启动消息队列、配置 RabbitMQ 容器、检查消息队列状态等需求时，务必使用此 skill。支持 start / stop / status / verify / logs 操作。
argument-hint: "[start|stop|status|verify|logs] [--env <env>] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]"
disable-model-invocation: true
---

> **路径约定**：本文档中 `<skill_dir>` 指 SKILL.md 所在目录（安装后为 `~/.claude/skills/setup-rabbitmq`）。

# setup-rabbitmq — RabbitMQ 4.0 生产级部署

帮助开发者使用 Docker Compose 在远程服务器上部署、管理和验证 RabbitMQ 4.0 容器（含 Management UI，生产级配置）。

## 文档职责说明

| 文档 | 读者 | 职责 |
|------|------|------|
| **SKILL.md** | Claude Code（AI） | 技能执行指令 — 定义 frontmatter、action 路由、执行流程 |
| **README.md** | 人（开发者/用户） | 入门指引文档 — 安装教程、配置说明、功能介绍、使用示例 |

## 配置

- 配置文件模板位于 `<skill_dir>/references/`
- 远程部署目录：`/opt/tech-stack/rabbitmq-{env}/`（env 由 `--env` 参数决定，如 `/opt/tech-stack/rabbitmq-dev/`）
- `rabbitmq.conf` 为纯静态配置（内存水位、磁盘水位、心跳）；账号、密码、vhost 通过 Docker 环境变量 `RABBITMQ_DEFAULT_USER/PASS/VHOST` 注入容器

## 用法

```
/setup-rabbitmq [action] [选项]

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
| `start` | 部署并启动 RabbitMQ 容器（默认 action） |
| `stop` | 停止并移除 RabbitMQ 容器 |
| `status` | 查看 RabbitMQ 容器运行状态 |
| `verify` | 验证 RabbitMQ 服务连通性和健康状态 |
| `logs` | 查看 RabbitMQ 容器日志 |

## 执行流程

1. 解析参数：提取 ENV（默认 dev，校验合法值）、ACTION（默认 start）、HOST（默认 localhost）、SSH_USER（默认 root）、SSH_PORT（默认 22）、AUTH（password 或 key）
   - ENV 合法值：`dev|sit|fat|uat|prod`；传入其他值立即报错退出
2. 读取 `<skill_dir>/actions/<action>.md` 按步骤执行

## 关键约束

- **管理员账号**：`.env` 必须替换 `CHANGE_ME_*` 占位符；guest 账号默认仅 localhost，业务连接必须使用自定义管理员
- **Quorum Queue**：业务声明队列时必须传 `x-queue-type: quorum`（Spring AMQP 4.x 支持）
- **Management UI 入口**：通过 infra-nginx 反代访问 `http://rabbitmq-{env}-ui.renew.com`，:15672 端口不直接暴露
- **Prometheus 抓取**：内置 `rabbitmq_prometheus` 插件暴露 :15692，setup-prometheus 直连 `rabbitmq-{env}.renew.com:15692/metrics` 采集

> 部署踩坑记录见 [pitfalls.md](references/pitfalls.md)，新问题也请记录到该文件。

## 多环境部署说明

每个环境（dev/sit/fat/uat/prod）部署**完全独立的物理实例**，通过 `--env` 参数区分。

| 配置项 | dev | sit | fat | uat | prod |
|--------|-----|-----|-----|-----|------|
| AMQP 直连域名 | `rabbitmq-dev.renew.com:5672` | `rabbitmq-sit.renew.com:5672` | `rabbitmq-fat.renew.com:5672` | `rabbitmq-uat.renew.com:5672` | `rabbitmq-prod.renew.com:5672` |
| Web UI 域名 | `rabbitmq-dev-ui.renew.com` | `rabbitmq-sit-ui.renew.com` | `rabbitmq-fat-ui.renew.com` | `rabbitmq-uat-ui.renew.com` | `rabbitmq-prod-ui.renew.com` |
| 部署目录 | `/opt/tech-stack/rabbitmq-dev/` | `/opt/tech-stack/rabbitmq-sit/` | `/opt/tech-stack/rabbitmq-fat/` | `/opt/tech-stack/rabbitmq-uat/` | `/opt/tech-stack/rabbitmq-prod/` |
| 容器名 | `tech-rabbitmq-dev` | `tech-rabbitmq-sit` | `tech-rabbitmq-fat` | `tech-rabbitmq-uat` | `tech-rabbitmq-prod` |
| 内存配额 | 512m | 512m | 1g | 1g | 2g |

**Spring Boot 接入**：`spring.rabbitmq.host=rabbitmq-${spring.profiles.active}.renew.com`，`spring.rabbitmq.virtual-host=/`。环境隔离已由独立实例保证。

**应用级 vhost 隔离（可选）**：同一实例内为多个应用切分独立 vhost 时执行：

```bash
docker exec tech-rabbitmq-${ENV} bash /init/01_init_env_vhosts.sh
```

## 踩坑记录规则

> 部署过程中遇到的问题，按以下流程处理：
> 1. **修复模板**：将 fix 写入 `references/` 配置文件或 `actions/start.md` 流程步骤，确保下次部署自动生效
> 2. **记录 pitfalls.md**：在 `references/pitfalls.md` 追加条目，注明问题现象、根因和修复方案
