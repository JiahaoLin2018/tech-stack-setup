---
name: setup-gitlab
description: 使用 Docker Compose 快速部署 GitLab EE 企业版（代码仓库 + CI/CD），含许可证自动激活。当用户需要部署 GitLab、搭建代码仓库、配置 CI/CD 平台、启动/停止/查看 GitLab 服务状态、激活许可证时，务必使用此 skill。即使用户只是提到"搭建 Git 服务"、"部署代码平台"、"本地 GitLab"等也应触发。
argument-hint: "[start|stop|status|verify|logs|activate|create-user] [--host <ip>] [--user <user>] [--password <pass>|--key <path>]"
disable-model-invocation: true
---

# setup-gitlab — GitLab EE Docker 部署工具

帮助开发者使用 Docker Compose 快速部署和管理 GitLab EE 企业版（含代码仓库、CI/CD 和企业级功能），并自动激活许可证。

> **路径约定**：本文档中 `<skill_dir>` 指 SKILL.md 所在目录（安装后为 `~/.claude/skills/setup-gitlab`）。

## 文档职责说明

| 文档 | 读者 | 职责 |
|------|------|------|
| **SKILL.md** | Claude Code（AI） | 技能执行指令、踩坑记录 |
| **README.md** | 人（开发者/用户） | 入门指引、配置说明 |
| **actions/activate.md** | Claude Code（AI） | 许可证激活详细流程 |

## 用法

```
/setup-gitlab [action] [选项]

action: start（默认）| stop | status | verify | logs | activate | create-user

选项:
  --host <ip>        部署目标 IP（必填）
  --user <user>      SSH 用户名（仅远程）
  --password <pass>  SSH 密码（仅远程）
  --ssh-port <n>     SSH 端口（默认: 22）
```

## 配置

- 配置模板位于 `<skill_dir>/references/conf/gitlab.rb.tpl`
- 许可证激活流程详见 `actions/activate.md`
- 远程部署目录：`/opt/tech-stack/gitlab/`

## Actions

| Action | 说明 |
|--------|------|
| `start` | 部署并启动 GitLab EE 容器（默认 action） |
| `stop` | 停止并移除 GitLab 容器 |
| `status` | 查看 GitLab 容器运行状态 |
| `verify` | 验证 GitLab 服务连通性和健康状态 |
| `logs` | 查看 GitLab 容器日志 |
| `activate` | 生成并激活 GitLab EE 企业版许可证 |
| `create-user` | 创建用户账号（默认禁用公开注册） |

## 执行流程

1. 解析参数：ACTION（默认 start）、HOST、SSH_USER、SSH_PORT、AUTH
2. 读取 `actions/<action>.md` 执行对应流程

## 重要说明

- 生产必须修改 .env 中所有 CHANGE_ME_* 值
- GitLab EE 较重，建议宿主机内存 4GB+，首次启动耗时 3-5 分钟
- 许可证文件保存在 `license/` 子目录，删除后需重新执行 `activate`
- **默认禁用公开注册**：账号由管理员统一分配

## 全局唯一服务说明

> 本 skill 为 **C 类全局唯一服务**，跨所有环境共享，全局仅部署 1 次。

| 约束项 | 固定值 |
|--------|--------|
| `--env` 参数 | **不接受**（传入即报错退出） |
| 部署目录 | `/opt/tech-stack/gitlab/` |
| 容器名 | `tech-gitlab` |
| 域名 | `gitlab.renew.com` |

## 配置管理

所有 GitLab 配置写入 `gitlab.rb`，由 `envsubst` 从 `conf/gitlab.rb.tpl` 模板和 `.env` 渲染生成。`docker-compose.yml` 不注入 `GITLAB_OMNIBUS_CONFIG`。

### 配置文件位置

| 宿主机路径 | 容器内路径 | 用途 |
|-----------|-----------|------|
| `./config/gitlab.rb` | `/etc/gitlab/gitlab.rb` | 主配置文件（唯一应修改） |
| `./config/gitlab-secrets.json` | `/etc/gitlab/gitlab-secrets.json` | 密钥存储（不要修改） |
| `./data/` | `/var/opt/gitlab/` | 运行时数据（会被 reconfigure 覆盖） |
| `./license/license_key.pub` | `.../.license_encryption_key.pub` | 许可证公钥（volume 挂载） |

### 修改配置流程

```bash
# 1. 编辑配置文件
vi /opt/tech-stack/gitlab/config/gitlab.rb

# 2. 应用配置
docker exec tech-gitlab gitlab-ctl reconfigure

# 3. 如需重启服务
docker exec tech-gitlab gitlab-ctl restart
```

> envsubst 渲染时仅替换 `${GITLAB_HOSTNAME}` 和 `${GITLAB_SSH_PORT}` 两个占位符，避免污染 gitlab.rb 中其他 `$` 开头的 Ruby 变量。

---

> 踩坑记录详见 [pitfalls.md](references/pitfalls.md)
