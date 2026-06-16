---
name: setup-otel-collector
description: OpenTelemetry Collector 0.120 统一可观测性数据接收网关 — 接收 OTLP Traces/Logs，路由至 Tempo/Loki 后端。B 类 Skill：--env nonprod|prod，部署两套（非生产共用/生产独立）。
argument-hint: "[start|stop|status|verify|logs] [--env nonprod|prod] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]"
disable-model-invocation: true
---

> **路径约定**：本文档中 `<skill_dir>` 指 SKILL.md 所在目录（安装后为 `~/.claude/skills/setup-otel-collector`）。

# setup-otel-collector — OpenTelemetry Collector 统一可观测性网关部署工具

帮助开发者部署和管理 OpenTelemetry Collector，作为统一可观测性数据接收网关，接收 OTLP 协议的 Traces 和 Logs 并路由至 Tempo/Loki 后端。

## 文档职责说明

| 文档 | 读者 | 职责 |
|------|------|------|
| **SKILL.md** | Claude Code（AI） | 技能执行指令 — 定义 frontmatter、action 路由、执行流程 |
| **README.md** | 人（开发者/用户） | 入门指引文档 — 安装教程、配置说明、功能介绍、使用示例 |

## 配置

- 配置模板位于 `<skill_dir>/references/`
- 远程部署目录：`/opt/tech-stack/otel-collector-{env}/`（env = nonprod 或 prod）

## 用法

```
/setup-otel-collector [action] [选项]

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
| `start` | 部署并启动 OpenTelemetry Collector（默认 action） |
| `stop` | 停止并移除 OTel Collector 容器 |
| `status` | 查看 OTel Collector 容器运行状态 |
| `verify` | 验证 OTel Collector 服务健康状态和 OTLP 连通性 |
| `logs` | 查看 OTel Collector 容器日志 |

## 执行流程

1. 解析参数：ENV（默认 nonprod，仅接受 nonprod|prod，传错报错退出）、ACTION（默认 start）、HOST（默认 localhost）、SSH_USER（默认 root）、SSH_PORT（默认 22）、AUTH
2. 读取 `<skill_dir>/actions/<action>.md` 执行对应操作

## 重要说明

- **B 类 --env 契约**：`--env nonprod` 部署非生产共用实例，`--env prod` 部署生产独立实例，传错立即报错退出
- OTel Collector 是应用发送 Traces 和 Logs 的统一入口（:4317 gRPC / :4318 HTTP）
- OTel Collector 占用宿主机 4317/4318 端口，Tempo 使用 14317/14318（宿主机映射端口）避免冲突
- 两条管道：Traces → `tempo-{env}.renew.com:14317`（OTLP gRPC），Logs → `loki-{env}.renew.com:3100/otlp`（OTLP HTTP）
- 应用 Metrics 通过 `/actuator/prometheus` 暴露，由 Prometheus 直接拉取（不经过 OTel Collector）
- 后端地址通过 `.env` 配置，域名须使用 `{service}-{env}.renew.com` 格式

## 注意事项

### 最小化镜像无 shell
`otel/opentelemetry-collector-contrib` 是最小化镜像，无 `/bin/sh`、`wget`、`curl`。healthcheck 使用 `["CMD", "/otelcol-contrib", "--version"]`，不能用 `CMD-SHELL`。

## 踩坑记录规则

> 部署过程中遇到的问题，按以下流程处理：
> 1. **修复模板**：将 fix 写入 `references/` 配置文件或 `actions/start.md` 流程步骤，确保下次部署自动生效
> 2. **记录 pitfalls.md**：在 `references/pitfalls.md` 追加问题现象、根因和修复方案
> 3. **同步 start.md**：若涉及新增步骤，更新 `actions/start.md` 并调整步骤编号
>
> 历史踩坑记录及解决方案详见 [pitfalls.md](references/pitfalls.md)，部署中遇到的新问题也请记录到该文件。
