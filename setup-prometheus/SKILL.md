---
name: setup-prometheus
description: Prometheus v3.2 + Alertmanager v0.28 指标监控与告警 — nonprod 采集 dev/sit/fat/uat 四套中间件，通过 env 标签隔离；prod 单套采集。B 类 Skill：--env nonprod|prod，部署两套。
argument-hint: "[start|stop|status|verify|logs] [--env nonprod|prod] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]"
disable-model-invocation: true
---

> **路径约定**：本文档中 `<skill_dir>` 指 SKILL.md 所在目录（安装后为 `~/.claude/skills/setup-prometheus`）。

# setup-prometheus — Prometheus + Alertmanager 指标监控与告警部署工具

帮助开发者部署和管理 Prometheus + Alertmanager 指标监控与告警体系，支持 Spring Boot Actuator 指标接入。

## 文档职责说明

| 文档 | 读者 | 职责 |
|------|------|------|
| **SKILL.md** | Claude Code（AI） | 技能执行指令 — 定义 frontmatter、action 路由、执行流程 |
| **README.md** | 人（开发者/用户） | 入门指引文档 — 安装教程、配置说明、功能介绍、使用示例 |

## 配置

- 配置模板位于 `<skill_dir>/references/`
- 远程部署目录：`/opt/tech-stack/prometheus-{env}/`（env = nonprod 或 prod）
- nonprod 使用 `prometheus.nonprod.yml`（含 dev/sit/fat/uat 四套 consul_sd + exporter）
- prod 使用 `prometheus.prod.yml`（单 prod 环境）

> **配置渲染例外说明**：本服务不使用 `.tpl` 模板 + `envsubst` 渲染机制。原因：Prometheus 配置为静态值（scrape_interval、alerting 规则等），动态服务发现通过 consul_sd 实现，无需模板渲染。配置文件按 `prometheus/`、`alertmanager/`、`rules/` 子目录组织，保留分类结构便于管理。

## 用法

```
/setup-prometheus [action] [选项]

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
| `start` | 部署并启动 Prometheus + Alertmanager（默认 action） |
| `stop` | 停止并移除容器 |
| `status` | 查看 Prometheus/Alertmanager 容器运行状态 |
| `verify` | 验证服务连通性和健康状态 |
| `logs` | 查看容器日志 |

## 执行流程

1. 解析参数：ENV（默认 nonprod，仅接受 nonprod|prod，传错报错退出）、ACTION（默认 start）、HOST（默认 localhost）、SSH_USER（默认 root）、SSH_PORT（默认 22）、AUTH
2. 读取 `<skill_dir>/actions/<action>.md` 执行对应操作

## 重要说明

- **B 类 --env 契约**：`--env nonprod` 部署非生产共用实例（采集 dev/sit/fat/uat 四套），`--env prod` 部署生产独立实例，传错立即报错退出
- **直连数据域名**：`prometheus-{env}.renew.com:9090`（写入 hosts.lan，Grafana 查询 + Tempo remote_write 入口）
- **Web UI 域名**：`prometheus-{env}-ui.renew.com`（infra-nginx 反代，不写 hosts.lan）
- **env 标签隔离**：nonprod Prometheus 通过各环境独立的 consul_sd_configs + relabel_configs 为每个 job 附加 `env` 标签
- 包含 Prometheus + Alertmanager 两个服务，Alertmanager Web UI：`alertmanager-{env}-ui.renew.com`
- 可视化面板由独立的 `setup-grafana` 提供（已预配置 Prometheus 数据源）

## 踩坑记录规则

> 部署过程中遇到的问题，按以下流程处理：
> 1. **修复模板**：将 fix 写入 `references/` 配置文件或 `actions/start.md` 流程步骤，确保下次部署自动生效
> 2. **记录 pitfalls.md**：在 `references/pitfalls.md` 追加问题现象、根因和修复方案
> 3. **同步 start.md**：若涉及新增步骤，更新 `actions/start.md` 并调整步骤编号
>
> 历史踩坑记录及解决方案详见 [pitfalls.md](references/pitfalls.md)，部署中遇到的新问题也请记录到该文件。
