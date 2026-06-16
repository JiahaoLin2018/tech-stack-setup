---
name: setup-grafana
description: Grafana 11.4 统一可视化看板 — 预配置 Prometheus/Tempo/Loki 三大数据源，Web UI 通过 infra-nginx 反代（grafana-nonprod-ui.renew.com）。B 类 Skill：--env nonprod|prod，部署两套。
argument-hint: "[start|stop|status|verify|logs] [--env nonprod|prod] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]"
disable-model-invocation: true
---

> **路径约定**：本文档中 `<skill_dir>` 指 SKILL.md 所在目录（安装后为 `~/.claude/skills/setup-grafana`）。

# setup-grafana — Grafana 统一可视化看板部署工具

帮助开发者部署和管理 Grafana 11.4 统一可视化看板，预配置 Prometheus、Tempo、Loki 三大数据源，实现 Metrics/Traces/Logs 三支柱统一查询。

## 文档职责说明

| 文档 | 读者 | 职责 |
|------|------|------|
| **SKILL.md** | Claude Code（AI） | 技能执行指令 — 定义 frontmatter、action 路由、执行流程 |
| **README.md** | 人（开发者/用户） | 入门指引文档 — 安装教程、配置说明、功能介绍、使用示例 |

## 配置

- 配置模板位于 `<skill_dir>/references/`
- 远程部署目录：`/opt/tech-stack/grafana-{env}/`（env = nonprod 或 prod）
- Web UI 域名：`grafana-{env}-ui.renew.com`（infra-nginx 反代 → :3000）

> **配置渲染例外说明**：本服务 `datasources.yml.tpl` 位于 `references/conf/grafana/provisioning/datasources/` 子目录（非规范路径），保留此结构是因为 Grafana provisioning 需要特定目录层级。渲染方式仍使用 envsubst。

## 用法

```
/setup-grafana [action] [选项]

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
| `start` | 部署并启动 Grafana 服务（默认 action） |
| `stop` | 停止并移除 Grafana 容器 |
| `status` | 查看 Grafana 容器运行状态 |
| `verify` | 验证 Grafana 服务连通性、数据源配置和健康状态 |
| `logs` | 查看 Grafana 容器日志 |

## 执行流程

1. 解析参数：ENV（默认 nonprod，仅接受 nonprod|prod，传错报错退出）、ACTION（默认 start）、HOST（默认 localhost）、SSH_USER（默认 root）、SSH_PORT（默认 22）、AUTH
2. 读取 `<skill_dir>/actions/<action>.md` 执行对应操作

## 重要说明

- **B 类 --env 契约**：`--env nonprod` 部署非生产共用实例，`--env prod` 部署生产独立实例，传错立即报错退出
- **Web UI 域名**：`grafana-{env}-ui.renew.com`（infra-nginx 反代 → :3000，不写 hosts.lan）
- Grafana 是纯可视化层，需配合 Prometheus、Tempo、Loki 等数据后端使用
- 已预配置三个数据源：`prometheus-{env}.renew.com:9090` / `tempo-{env}.renew.com:3200` / `loki-{env}.renew.com:3100`
- 支持 Trace ↔ Log 双向跳转、Trace → Metrics 关联、Service Map、Node Graph
- **透明支持 Spring Boot 双方案**：Micrometer + OTel Bridge (SB 3.x) / OTel Java Agent (SB 2.x)，详见 README.md Spring Boot 可观测性集成章节
- 密码通过 `.env` 配置，首次登录后建议修改

## 踩坑记录规则

> 部署过程中遇到的问题，按以下流程处理：
> 1. **修复模板**：将 fix 写入 `references/` 配置文件或 `actions/start.md` 流程步骤，确保下次部署自动生效
> 2. **记录 pitfalls.md**：在 `references/pitfalls.md` 追加问题现象、根因和修复方案
> 3. **同步 start.md**：若涉及新增步骤，更新 `actions/start.md` 并调整步骤编号
>
> 历史踩坑记录及解决方案详见 [pitfalls.md](references/pitfalls.md)，部署中遇到的新问题也请记录到该文件。
