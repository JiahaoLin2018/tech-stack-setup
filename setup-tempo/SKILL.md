---
name: setup-tempo
description: Grafana Tempo 2.7 分布式链路追踪后端 — 接收 OTel Collector 推送的 Trace（:14317 gRPC / :14318 HTTP），Grafana 查询 :3200。B 类 Skill：--env nonprod|prod，部署两套（非生产共用/生产独立）。
argument-hint: "[start|stop|status|verify|logs] [--env nonprod|prod] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]"
disable-model-invocation: true
---

> **路径约定**：本文档中 `<skill_dir>` 指 SKILL.md 所在目录（安装后为 `~/.claude/skills/setup-tempo`）。

# setup-tempo — Grafana Tempo 分布式链路追踪部署工具

帮助开发者部署和管理 Grafana Tempo 2.7 分布式链路追踪后端，支持 OTLP/Zipkin 协议接收 Trace 数据，与 Grafana 深度集成。

## 文档职责说明

| 文档 | 读者 | 职责 |
|------|------|------|
| **SKILL.md** | Claude Code（AI） | 技能执行指令 — 定义 frontmatter、action 路由、执行流程 |
| **README.md** | 人（开发者/用户） | 入门指引文档 — 安装教程、配置说明、功能介绍、使用示例 |

## 配置

- 配置模板位于 `<skill_dir>/references/`
- 远程部署目录：`/opt/tech-stack/tempo-{env}/`（env = nonprod 或 prod）
- `tempo-config.yml.tpl` 为配置模板，启动时通过 `envsubst` 渲染 `.env` 变量生成最终 `tempo-config.yml`

## 用法

```
/setup-tempo [action] [选项]

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
| `start` | 部署并启动 Tempo 服务（默认 action） |
| `stop` | 停止并移除 Tempo 容器 |
| `status` | 查看 Tempo 容器运行状态 |
| `verify` | 验证 Tempo 服务连通性和健康状态 |
| `logs` | 查看 Tempo 容器日志 |

## 执行流程

1. 解析参数：ENV（默认 nonprod，仅接受 nonprod|prod，传错报错退出）、ACTION（默认 start）、HOST（默认 localhost）、SSH_USER（默认 root）、SSH_PORT（默认 22）、AUTH
2. 读取 `<skill_dir>/actions/<action>.md` 执行对应操作

## 重要说明

- **B 类 --env 契约**：`--env nonprod` 部署非生产共用实例，`--env prod` 部署生产独立实例，传错立即报错退出
- **端口说明**：宿主机端口 `:14317`（OTLP gRPC）/ `:14318`（OTLP HTTP）映射到容器内 `:4317`/`:4318`，避免与同机 OTel Collector 冲突；Grafana 查询 API 使用 `:3200`
- 数据接入域名：`tempo-{env}.renew.com:14317`（OTel Collector 推送入口）
- Grafana 查询域名：`tempo-{env}.renew.com:3200`（直连数据端口，写入 hosts.lan）
- Tempo 仅作为 Trace 后端存储，需配合 Grafana 进行可视化查询
- 与 setup-prometheus 中的 Prometheus 集成可生成 service graph 和 span metrics
- **Resource Attributes 保留**：Tempo 原生保留 OTLP resource attributes（包括 `deployment.environment`），无需额外配置。该属性由 OTel Collector 的 resource processor 注入，Tempo 只需透传即可支持按环境查询 traces
- `.env` 统一管理所有可变配置（端口、Prometheus 地址、保留时长、资源限制）

## 踩坑记录规则

> 部署过程中遇到的问题，按以下流程处理：
> 1. **修复模板**：将 fix 写入 `references/` 配置文件或 `actions/start.md` 流程步骤，确保下次部署自动生效
> 2. **记录 pitfalls.md**：在 `references/pitfalls.md` 追加问题现象、根因和修复方案
> 3. **同步 start.md**：若涉及新增步骤，更新 `actions/start.md` 并调整步骤编号
>
> 历史踩坑记录及解决方案详见 [pitfalls.md](references/pitfalls.md)，部署中遇到的新问题也请记录到该文件。
