# Task 03 — GitLab EE 部署

> 企业级代码托管 + CI/CD 管理平台。对应 architecture-blueprint.md 第五部分阶段一 1-3。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS）已完成 |
| 环境要求 | Docker + Docker Compose 已安装；本机内存预留 ≥ 8 GB |
| 跨机部署 | 必须与 infra-nginx 跨主机（`:2222` 端口冲突） |
| 许可证 | 企业版许可证文件（如有） |

## 架构约束

- 全局唯一服务（C 类，不接受 `--env`），跨所有环境共享
- 反代由 task-02 已预配置，本任务部署到位即生效
- 容器宿主机端口：`8929(HTTP，容器 :80) / 2222(SSH，容器 :22)`

## 关键 .env 配置

| 变量 | 说明 |
|------|------|
| `GITLAB_HOSTNAME` | `gitlab.renew.com` |
| `GITLAB_HTTP_PORT` | `8929`（容器内 :80 → 宿主机 :8929） |
| `GITLAB_SSH_PORT` | `2222` |
| `GITLAB_MEMORY_LIMIT` | `4g` |
| `GITLAB_MEMORY_RESERVATION` | `2g` |

> 初始 root 密码由 GitLab 首次启动时生成（`docker exec tech-gitlab cat /etc/gitlab/initial_root_password`），登录后立即修改。
> 企业版许可证（如有）首次登录后通过 Admin → Subscription 上传。

## 部署命令

```bash
/setup-gitlab start --host <GITLAB_IP> --user <USER> --password <PASS>
/setup-gitlab activate --host <GITLAB_IP> --user <USER> --password <PASS>   # 企业版许可证生成与挂载（首次部署）
/setup-gitlab verify --host <GITLAB_IP> --user <USER> --password <PASS>
```

## 验证标准

- [ ] `http://gitlab.renew.com` 可登录（infra-nginx 反代自动生效）
- [ ] `ssh -T -p 2222 git@gitlab.renew.com` 可建立 SSH 连接（infra-nginx :2222 透传）
- [ ] 企业版许可证已激活（Admin → Settings → General → Add License）
- [ ] `docker exec tech-gitlab gitlab-ctl status` 内部服务全部 `run:`

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 4-8 GB | 2-4 核 | 200 GB+ |

## 并行说明

与 task-04（Nexus）、task-05（Harbor）可全部并行（三者无相互依赖）。

## 注意事项

- GitLab 启动较慢（首次 5-10 分钟），等 healthcheck 全绿再继续
- 初始 root 密码记录到 `env/gitlab.md`（**禁止提交 git**）
- 首次登录后必须修改 root 密码并启用 2FA
- task-33 / 48（GitLab Runner）需要从 Settings → CI/CD → Runners 获取 Registration Token

## 后续步骤

- 创建组织架构（如 `infra` / `business` / `demo` 顶级 group）
- 准备 Runner Registration Token（部署 task-33 时使用）
- 推送 OTel Agent 等基础工具仓库（如需）
