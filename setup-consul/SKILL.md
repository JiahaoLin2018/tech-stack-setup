---
name: setup-consul
description: 使用 Docker Compose 部署和管理 Consul 1.20 服务注册与发现。支持多环境独立部署（dev/sit/fat/uat/prod 各一套完全独立实例），每环境独立容器、目录和域名，确保服务注册信息不跨环境污染。当开发者需要启动、停止、查看状态、验证或查看日志 Consul 服务时触发此 skill。
argument-hint: "[start|stop|status|verify|logs] [--env dev|sit|fat|uat|prod] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]"
disable-model-invocation: true
---

> **路径约定**：本文档中 `<skill_dir>` 指 SKILL.md 所在目录（安装后为 `~/.claude/skills/setup-consul`）。

# setup-consul — Consul 服务注册与发现部署

提供 Consul 1.20 的完整生命周期管理，支持多环境独立部署和远程服务器 SSH 部署。

## 文档职责说明

| 文档 | 读者 | 职责 |
|------|------|------|
| **SKILL.md** | Claude Code（AI） | 技能执行指令 — 定义 frontmatter、action 路由、执行流程 |
| **README.md** | 人（开发者/用户） | 入门指引文档 — 安装教程、配置说明、功能介绍、使用示例 |

## 配置

- 配置文件模板位于 `<skill_dir>/references/`
- 远程部署目录：`/opt/tech-stack/consul-{env}/`（每环境独立目录）

## 用法

```
/setup-consul [action] [选项]

action: start（默认）| stop | status | verify | logs

选项:
  --env <env>        部署环境（dev|sit|fat|uat|prod，默认: dev；传入其他值报错退出）
  --host <ip>        部署目标 IP（默认: localhost）
  --user <user>      SSH 用户名（默认: root，仅远程）
  --password <pass>  SSH 密码（仅远程，与 --key 二选一）
  --key <path>       SSH 私钥路径（仅远程，与 --password 二选一）
  --ssh-port <n>     SSH 端口（默认: 22）
```

## `--env` 参数契约（A 类 — 环境级完全独立）

| 参数 | 容器名 | 部署目录 | 直连域名 |
|------|--------|---------|---------|
| `--env dev`（默认） | tech-consul-dev | /opt/tech-stack/consul-dev/ | consul-dev.renew.com:8500 |
| `--env sit` | tech-consul-sit | /opt/tech-stack/consul-sit/ | consul-sit.renew.com:8500 |
| `--env fat` | tech-consul-fat | /opt/tech-stack/consul-fat/ | consul-fat.renew.com:8500 |
| `--env uat` | tech-consul-uat | /opt/tech-stack/consul-uat/ | consul-uat.renew.com:8500 |
| `--env prod` | tech-consul-prod | /opt/tech-stack/consul-prod/ | consul-prod.renew.com:8500 |
| 传入其他值 | — | — | 立即报错退出 |

## Actions

| Action | 说明 |
|--------|------|
| `start` | 部署并启动指定环境的 Consul 容器（默认 action） |
| `stop` | 停止并移除指定环境的 Consul 容器 |
| `status` | 查看指定环境的 Consul 容器运行状态 |
| `verify` | 验证指定环境的 Consul 服务连通性和健康状态 |
| `logs` | 查看指定环境的 Consul 容器日志 |

## 执行流程

1. 解析参数：提取 ENV（默认 dev，传入无效值立即报错退出）、ACTION（默认 start）、HOST（默认 localhost）、SSH_USER（默认 root）、SSH_PORT（默认 22）、AUTH（password 或 key）
2. 推导：`DEPLOY_DIR=/opt/tech-stack/consul-${ENV}`、`CONTAINER_NAME=tech-consul-${ENV}`
3. 读取 `<skill_dir>/actions/<action>.md` 按步骤执行

> **变量约定**：`<skill_dir>` 和 `${CLAUDE_SKILL_DIR}` 均指 Skill 安装目录（`~/.claude/skills/setup-consul`），由 Claude Code 运行时自动注入。

## SSH_CMD 约定

action 文件中的 `SSH_CMD "..."` 是伪命令，执行时根据认证方式展开：

```bash
# 密码模式
sshpass -p "${SSH_PASSWORD}" ssh -o StrictHostKeyChecking=no -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} "..."

# 密钥模式
ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} "..."
```

## 多环境部署信息

| 配置项 | dev | sit | fat | uat | prod |
|--------|-----|-----|-----|-----|------|
| 直连域名 | consul-dev.renew.com | consul-sit.renew.com | consul-fat.renew.com | consul-uat.renew.com | consul-prod.renew.com |
| Web UI 域名 | consul-dev-ui.renew.com | consul-sit-ui.renew.com | consul-fat-ui.renew.com | consul-uat-ui.renew.com | consul-prod-ui.renew.com |
| Web UI 入口 | infra-nginx 代理 | infra-nginx 代理 | infra-nginx 代理 | infra-nginx 代理 | infra-nginx 代理 |
| ACL | 关闭 | 关闭 | 关闭 | 关闭 | **必须开启** |

> 直连域名已写入 hosts.lan，访问时必须带端口：`consul-{env}.renew.com:8500`。Web UI 域名由泛解析→infra-nginx 代理，不写入 hosts.lan。

## Spring Boot 接入

```yaml
spring:
  cloud:
    consul:
      host: consul-${ENV}.renew.com   # 按部署环境选择，如 consul-dev.renew.com
      port: 8500
      discovery:
        service-name: ${spring.application.name}
        tags: metrics                 # 必填：Prometheus consul_sd 通过此 tag 过滤 Spring Boot 服务
        health-check-interval: 10s
```

> **`tags: metrics` 是强制契约**：Prometheus（`setup-prometheus`）通过 `consul_sd_configs.tags: ['metrics']` 发现业务服务并抓取 `/actuator/prometheus`。未打 `metrics` tag 的服务**不会出现在 Prometheus 监控列表中**。

## 重要说明

- 每环境完全独立部署，互不影响，无标签隔离机制
- 生产环境（prod）必须在 .env 中设置完整 `CONSUL_ACL_CONFIG` 块开启 ACL
- 生产环境必须修改 .env 中所有 `CHANGE_ME_*` 值

## 踩坑记录规则

> 部署过程中遇到的问题，按以下流程处理：
> 1. **修复模板**：将 fix 写入 `references/` 配置文件或 `actions/start.md` 流程步骤，确保下次部署自动生效
> 2. **记录 pitfalls.md**：在 `references/pitfalls.md` 追加说明（仅记录无法自动化的操作风险和使用指引）
> 3. **同步 start.md**：若涉及新增步骤，更新 `actions/start.md` 并调整步骤编号

> 历史踩坑记录及解决方案详见 [pitfalls.md](references/pitfalls.md)，部署中遇到的新问题也请记录到该文件。
