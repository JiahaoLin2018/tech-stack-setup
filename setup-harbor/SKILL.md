---
name: setup-harbor
description: 使用官方安装器部署 Harbor 私有 Docker 镜像仓库，含 Trivy 漏洞扫描。当用户需要部署 Harbor、搭建私有镜像仓库、配置 Docker Registry、管理镜像存储时，务必使用此 skill。即使用户只是提到"私有仓库"、"镜像仓库"、"Harbor 搭建"等也应触发。
argument-hint: "[start|stop|status|verify|logs] [--host <ip>] [--user <user>] [--password <pass>|--key <path>] [--ssh-port <n>]"
disable-model-invocation: true
---

> **路径约定**：本文档中 `<skill_dir>` 指 SKILL.md 所在目录（安装后为 `~/.claude/skills/setup-harbor`）。

# setup-harbor — Harbor 私有镜像仓库部署工具

帮助开发者使用 Harbor 官方安装器部署和管理私有 Docker 镜像仓库（含 Trivy 漏洞扫描）。

## 文档职责说明

| 文档 | 读者 | 职责 |
|------|------|------|
| **SKILL.md** | Claude Code（AI） | 技能执行指令 — 定义 frontmatter、action 路由、执行流程 |
| **README.md** | 人（开发者/用户） | 入门指引文档 — 安装教程、配置说明、功能介绍、使用示例 |

## 配置

- 配置模板位于 `<skill_dir>/references/`
- 远程部署目录：`/opt/tech-stack/harbor/`

## 用法

```
/setup-harbor [action] [选项]

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
| `start` | 部署并启动 Harbor 服务（默认 action） |
| `stop` | 停止并移除 Harbor 服务 |
| `status` | 查看 Harbor 各组件运行状态 |
| `verify` | 验证 Harbor 服务连通性和健康状态 |
| `logs` | 查看 Harbor 容器日志 |

## 执行流程

1. 解析参数：ACTION（默认 start）、HOST（默认 localhost）、SSH_USER（默认 root）、SSH_PORT（默认 22）、AUTH（--password 或 --key）
2. 读取 `<skill_dir>/actions/<action>.md` 执行对应流程

## 目录结构

```
setup-harbor/
├── SKILL.md           # 技能入口（本文件）
├── actions/           # 动作执行流程
│   ├── start.md       # 部署流程
│   ├── stop.md
│   ├── status.md
│   ├── verify.md
│   └── logs.md
├── references/        # 配置模板
│   ├── .env.example
│   ├── pitfalls.md    # 踩坑记录
│   └── conf/
│       └── harbor.yml.tpl
├── cache/             # 本地缓存（安装包下载）
│   └── harbor-offline-installer-*.tgz
└── README.md
```

## 重要说明

- Harbor 使用官方安装器（`./install.sh`）而非手动 docker-compose
- 生产必须修改 harbor.yml 中所有 CHANGE_ME_* 值
- `harbor.yml` 中 `hostname` 固定为 `harbor.renew.com`（项目统一域名）
- **安装包下载**：远程服务器通常无法访问 GitHub，必须手工下载后上传，缓存到 `<skill_dir>/cache/`
- **HTTP Registry**：若使用 HTTP（非 HTTPS），客户端 Docker 需配置 `insecure-registries: ["harbor.renew.com"]`（无端口）

## 全局唯一服务说明

> 本 skill 为 **C 类全局唯一服务**，跨所有环境共享，全局仅部署 1 次。

| 约束项 | 固定值 |
|--------|--------|
| `--env` 参数 | **不接受**（传入即报错退出） |
| 部署目录 | `/opt/tech-stack/harbor/` |
| 容器名前缀 | `harbor-*`（Harbor 官方安装器命名） |
| 域名 | `harbor.renew.com` |

> 踩坑记录详见 [pitfalls.md](references/pitfalls.md)
