---
name: setup-dns
description: 使用 Docker 部署 dnsmasq 局域网 DNS 服务器，为整套技术栈提供域名解析（*.renew.com），支持远程部署。当用户提到部署 DNS、配置域名解析、dnsmasq、局域网域名、renew.com 等需求时触发此 skill。支持 start / stop / status / verify / logs / configure 操作。configure 操作可将目标机器的 DNS 指向 dnsmasq 服务器。
argument-hint: "[start|stop|status|verify|logs|configure] [--host <ip>] [--dns-server <ip>] [--user <user>] [--password <pass>|--key <path>]"
disable-model-invocation: true
---

> **路径约定**：本文档中 `<skill_dir>` 指 SKILL.md 所在目录（安装后为 `~/.claude/skills/setup-dns`）。

# setup-dns — 局域网 DNS 服务（dnsmasq）

使用 Docker 部署 dnsmasq，为整套微服务技术栈提供局域网内域名解析。所有基础设施服务通过 `*.renew.com` 域名访问，无需记忆 IP 地址。

## 文档职责说明

| 文档 | 读者 | 职责 |
|------|------|------|
| **SKILL.md** | Claude Code（AI） | 技能执行指令 — 定义 frontmatter、action 路由、执行约束 |
| **README.md** | 人（开发者/用户） | 入门指引文档 — 安装教程、配置说明、功能介绍、使用示例 |

## 配置

- 配置文件模板位于 `<skill_dir>/references/`
- 远程部署目录：`/opt/tech-stack/dns/`
- 域名映射文件：`hosts.lan`（只维护②/④ 直连层——需精确指定 IP 的基础设施数据端口域名）
- 泛解析配置：`dnsmasq.conf` 中的 `address=/.renew.com/<infra-nginx所在IP>`（兜底所有未定义的 `*.renew.com`）

> **配置渲染例外说明**：本服务不使用 `.tpl` 模板 + `envsubst` 渲染机制。原因：`dnsmasq.conf` 中仅一个变量 `${INFRA_NGINX_IP}`，使用本地 Python 替换后上传，简化流程。配置文件位于 `references/` 根目录（非 `references/conf/`），保持简单结构。

## 用法

```
/setup-dns [action] [选项]

action: start（默认）| stop | status | verify | logs | configure

选项:
  --host <ip>        部署目标 IP（默认: localhost）；configure 时此处是"要配置 DNS 的目标机器"
  --dns-server <ip>  dnsmasq 服务器 IP（仅 configure 必需，即 start 时部署 dnsmasq 的机器 IP）
  --user <user>      SSH 用户名（默认: root，仅远程）
  --password <pass>  SSH 密码（仅远程，与 --key 二选一）
  --key <path>       SSH 私钥路径（仅远程，与 --password 二选一）
  --ssh-port <n>     SSH 端口（默认: 22）
```

## Actions

| Action | 说明 |
|--------|------|
| `start` | 部署并启动 dnsmasq 容器（默认 action） |
| `stop` | 停止 dnsmasq 容器（容器保留，可用 start 快速恢复；如需彻底移除请手动 `docker rm tech-dns`） |
| `status` | 查看 dnsmasq 容器运行状态和解析统计 |
| `verify` | 验证域名解析是否正常（测试 *.renew.com 解析） |
| `logs` | 查看 dnsmasq 容器日志（含 DNS 查询记录） |
| `configure` | 配置目标机器的 DNS 指向 dnsmasq（修改 resolv.conf 或 systemd-resolved） |

## 执行流程

1. 解析参数：提取 ACTION（默认 start）、HOST（默认 localhost）、DNS_SERVER_IP（仅 configure 用）、SSH_USER（默认 root）、SSH_PORT（默认 22）、AUTH（password 或 key）
2. **--env 校验**：若传入 `--env` 参数则立即报错退出（C 类全局唯一服务）
3. 读取 `<skill_dir>/actions/<action>.md` 按步骤执行

## 职责边界

dnsmasq **只负责内部基础设施域名解析**，业务域名的 DNS 解析和路由访问控制均不在 dnsmasq 范围内。

| 域名类型 | 示例 | 管理方 |
|---------|------|--------|
| 基础设施域名 | `mysql-dev.renew.com` | hosts.lan 精确映射 |
| 内部 Web UI | `grafana-nonprod-ui.renew.com` | dnsmasq.conf 泛解析兜底 → infra-nginx 反代 |
| 业务前端/API | `demo.fat.web.renew.com` | 泛解析兜底 → infra-nginx → K3s Traefik |

## 关键约束

### --env 参数（C 类：全局唯一，不接受）

setup-dns 是全局唯一服务，传入 `--env` 参数将**立即报错退出**：
```
❌ setup-dns 是全局唯一服务（C 类），不接受 --env 参数，请移除后重试。
```

### 域名四层规范（hosts.lan 写入判断）

| 层级 | 命名规则 | 是否写入 hosts.lan | 示例 |
|------|---------|-----------------|------|
| ① 全局唯一 | `{service}.renew.com` | **否**（泛解析→infra-nginx 代理） | `gitlab.renew.com` |
| ② 域级共用 — 数据端口 | `{service}-{nonprod\|prod}.renew.com` | **是**（直连数据端口） | `otel-nonprod.renew.com` |
| ② 域级共用 — Web UI | `{service}-{nonprod\|prod}-ui.renew.com` | **否**（泛解析→infra-nginx 代理） | `grafana-nonprod-ui.renew.com` |
| ③ 非生产独有 | `{service}.renew.com` | **否**（泛解析→infra-nginx 代理） | `apollo.renew.com` |
| ④ 环境级直连 | `{service}-{env}.renew.com` | **是**（直连数据端口） | `mysql-dev.renew.com` |
| ④ 环境级 Web UI | `{service}-{env}-ui.renew.com` | **否**（泛解析→infra-nginx 代理） | `consul-dev-ui.renew.com` |
| ④ Apollo Config | `apollo-config-{env}.renew.com` | **否**（泛解析→infra-nginx 代理） | `apollo-config-fat.renew.com` |
| ④ 业务应用 | `{project}.{env}.{web\|api}.renew.com` | **否**（泛解析→infra-nginx→K3s） | `zoro.fat.web.renew.com` |

**核心规则**：hosts.lan 只写需要 Pod/微服务 **直接 TCP 连接** 的域名；通过 infra-nginx HTTP 反代访问的域名全部不写，泛解析自动处理。

### DNS 解析优先级

`hosts.lan` 精确匹配 > `address=/.renew.com/${INFRA_NGINX_IP}` 泛解析 > 上游 DNS 转发

### 必须使用 network_mode: host

dnsmasq 容器必须使用 `network_mode: host`。bridge 网络 + docker-proxy 端口映射时 Docker DNS 转发 UDP 查询会超时，host 模式下直接监听宿主机 :53，所有容器自动可用。Web UI 通过 `PORT` 环境变量改为监听 :5380，避免与其他服务端口冲突。

### hosts.lan 变更须知

修改 `hosts.lan` 后必须重启容器：`docker restart tech-dns`。

> 历史踩坑记录及解决方案详见 [pitfalls.md](references/pitfalls.md)，部署中遇到的新问题也请记录到该文件。

## 踩坑记录规则

> 部署过程中遇到的问题，按以下流程处理：
> 1. **修复模板**：将 fix 写入 `references/` 配置文件或 `actions/start.md` 流程步骤，确保下次部署自动生效
> 2. **记录 pitfalls.md**：在 `references/pitfalls.md` 中追加问题记录（现象、根因、修复方案）
> 3. **同步 start.md**：若涉及新增步骤，更新 `actions/start.md` 并调整步骤编号
