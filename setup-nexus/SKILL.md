---
name: setup-nexus
description: 使用 Docker Compose 部署和管理 Nexus Repository OSS 3 Maven 私服。当开发者需要启动、停止、查看状态、验证或查看日志 Nexus 服务时触发此 skill。
argument-hint: "[start|stop|status|verify|logs] [--host <ip>] [--user <user>] [--password <pass>|--key <path>] [--ssh-port <n>]"
disable-model-invocation: true
---

> **路径约定**：本文档中 `<skill_dir>` 指 SKILL.md 所在目录（安装后为 `~/.claude/skills/setup-nexus`）。

# setup-nexus — Nexus Repository OSS 3 部署

提供 Nexus Repository OSS 3 的完整生命周期管理，支持远程服务器 SSH 部署。

## 文档职责说明

| 文档 | 读者 | 职责 |
|------|------|------|
| **SKILL.md** | Claude Code（AI） | 技能执行指令 — 定义 frontmatter、action 路由、执行流程 |
| **README.md** | 人（开发者/用户） | 入门指引文档 — 安装教程、配置说明、功能介绍、使用示例 |

## 配置

- `references/docker-compose.yml` + `.env.example` 直接落地，无 `.tpl` 渲染（Nexus 应用配置通过首次启动 Web UI 向导完成：管理员密码在 UI 中设置，仓库与权限在初始化时创建）
- 远程部署目录：`/opt/tech-stack/nexus/`

## 用法

```
/setup-nexus [action] [选项]

action: start（默认）| stop | status | verify | logs

选项:
  --host <ip>        部署目标 IP（默认: localhost）
  --user <user>      SSH 用户名（默认: root，仅远程）
  --password <pass>  SSH 密码（仅远程，与 --key 二选一）
  --key <path>       SSH 私钥路径（仅远程，与 --password 二选一）
  --ssh-port <n>     SSH 端口（默认: 22）
```

## Actions

| Action | 说明 |
|--------|------|
| `start` | 部署并启动 Nexus 容器（默认 action） |
| `stop` | 停止并移除 Nexus 容器 |
| `status` | 查看 Nexus 容器运行状态 |
| `verify` | 验证 Nexus 服务连通性和健康状态 |
| `logs` | 查看 Nexus 容器日志 |

## 执行流程

1. 解析参数：提取 ACTION（默认 start）、HOST（默认 localhost）、SSH_USER（默认 root）、SSH_PORT（默认 22）、AUTH（password 或 key）
2. 读取 `<skill_dir>/actions/<action>.md` 按步骤执行

## 重要说明

- Nexus 首次启动约需 60-90 秒，健康检查 start_period 为 120 秒
- 生产环境应根据实际资源调整 .env 中 JVM 参数和域名配置

## 全局唯一服务说明

> 本 skill 为 **C 类全局唯一服务**，跨所有环境共享，全局仅部署 1 次。

| 约束项 | 固定值 |
|--------|--------|
| `--env` 参数 | **不接受**（传入即报错退出） |
| 部署目录 | `/opt/tech-stack/nexus/` |
| 容器名 | `tech-nexus` |
| 域名 | `nexus.renew.com` |

> 踩坑记录详见 [pitfalls.md](references/pitfalls.md)
