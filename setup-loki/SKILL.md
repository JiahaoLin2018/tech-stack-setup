---
name: setup-loki
description: Grafana Loki 3.5 日志聚合系统 — OTel Collector 推送日志（:3100 OTLP HTTP），通过 env 标签逻辑隔离多环境日志。B 类 Skill：--env nonprod|prod，部署两套（非生产共用/生产独立）。
argument-hint: "[start|stop|status|verify|logs] [--env nonprod|prod] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]"
disable-model-invocation: true
---

> **路径约定**：本文档中 `<skill_dir>` 指 SKILL.md 所在目录（安装后为 `~/.claude/skills/setup-loki`）。

# setup-loki — Grafana Loki 日志聚合系统部署工具

帮助开发者部署和管理 Grafana Loki 3.5 日志聚合系统，支持轻量级日志收集、标签索引和 LogQL 查询，与 Grafana 深度集成。

## 文档职责说明

| 文档 | 读者 | 职责 |
|------|------|------|
| **SKILL.md** | Claude Code（AI） | 技能执行指令 — 定义 frontmatter、action 路由、执行流程 |
| **README.md** | 人（开发者/用户） | 入门指引文档 — 安装教程、配置说明、功能介绍、使用示例 |

## 配置

- 配置模板位于 `<skill_dir>/references/`
- 远程部署目录：`/opt/tech-stack/loki-{env}/`（env = nonprod 或 prod）

## 用法

```
/setup-loki [action] [选项]

action: start（默认）| stop | status | verify | logs

选项:
  --env <env>        部署环境，nonprod|prod（默认: nonprod；传错立即报错退出）
  --host <ip>        部署目标 IP（默认: localhost）
  --user <user>      SSH 用户名（默认: root，仅远程）
  --password <pass>  SSH 密码（仅远程，与 --key 二选一）
  --key <path>       SSH 私钥路径（仅远程，与 --password 二选一）
  --ssh-port <n>     SSH 端口（默认: 22）
```

## Actions

| Action | 说明 |
|--------|------|
| `start` | 部署并启动 Loki 服务（默认 action） |
| `stop` | 停止并移除 Loki 容器 |
| `status` | 查看 Loki 容器运行状态 |
| `verify` | 验证 Loki 服务连通性和健康状态 |
| `logs` | 查看 Loki 容器日志 |

## 执行流程

1. 解析参数：ENV（默认 nonprod，仅接受 nonprod|prod，传错报错退出）、ACTION（默认 start）、HOST（默认 localhost）、SSH_USER（默认 root）、SSH_PORT（默认 22）、AUTH
2. 读取 `<skill_dir>/actions/<action>.md` 执行对应操作

## 重要说明

- **B 类 --env 契约**：`--env nonprod` 部署非生产共用实例，`--env prod` 部署生产独立实例，传错立即报错退出
- 直连数据域名：`loki-{env}.renew.com:3100`（OTel Collector 推送 + Grafana 查询，写入 hosts.lan）
- **env 标签逻辑隔离**：Loki 通过 `otlp_config.resource_attributes` 将 `deployment.environment` 索引为 `deployment_environment` 标签（Loki 自动将点号转为下划线），实现多环境日志逻辑隔离
- 使用文件系统存储，适合中小规模日志场景
- 数据保留期通过 `loki-config.yml` 中的 `retention_period` 配置（默认 7 天）
- Grafana 数据源 URL：`http://loki-{env}.renew.com:3100`

## 踩坑记录规则

> 部署过程中遇到的问题，按以下流程处理：
> 1. **修复模板**：将 fix 写入 `references/` 配置文件或 `actions/start.md` 流程步骤，确保下次部署自动生效
> 2. **记录 pitfalls.md**：在 `references/pitfalls.md` 追加问题现象、根因和修复方案
> 3. **同步 start.md**：若涉及新增步骤，更新 `actions/start.md` 并调整步骤编号
>
> 历史踩坑记录及解决方案详见 [pitfalls.md](references/pitfalls.md)，部署中遇到的新问题也请记录到该文件。
