# setup-gitlab — 入门指引

使用 Docker Compose 部署 GitLab EE 企业版（代码仓库 + CI/CD + 企业级功能），含许可证自动激活，支持本地和远程两种部署模式。

## 安装教程

在项目根目录下运行：

```bash
bash setup-gitlab/install.sh
```

脚本会将 `setup-gitlab/` 全部内容复制到 `~/.claude/skills/setup-gitlab/`。

## 目录结构

```
setup-gitlab/
├── SKILL.md                    # Skill 路由指令（Claude 读取）
├── README.md                   # 入门指引（人类读取）
├── install.sh                  # 安装脚本
├── actions/
│   ├── start.md                # 启动流程（含本地/远程模式）
│   ├── stop.md                 # 停止流程
│   ├── status.md               # 状态查看
│   ├── verify.md               # 服务验证
│   ├── logs.md                 # 日志查看
│   ├── activate.md             # 许可证激活流程
│   └── create-user.md          # 用户创建指引
└── references/
    ├── docker-compose.yml      # 生产级 Compose 配置
    ├── .env.example            # 环境变量模板
    ├── pitfalls.md             # 踩坑记录
    └── conf/
        └── gitlab.rb.tpl       # GitLab 配置模板（envsubst 渲染）
```

## 用法

```
/setup-gitlab [action] [选项]
```

### 参数说明

| 参数 | 说明 |
|------|------|
| `start`（默认） | 启动 GitLab EE |
| `stop` | 停止 GitLab |
| `status` | 查看服务状态 |
| `verify` | 验证服务健康 |
| `logs` | 查看容器日志 |
| `activate` | 激活企业版许可证 |
| `create-user` | 用户创建指引（默认禁用公开注册） |

### 选项说明

| 选项 | 默认值 | 说明 |
|------|--------|------|
| `--host <ip>` | localhost | 部署目标 IP 或域名 |
| `--user <user>` | root | SSH 用户名（仅远程） |
| `--password <pass>` | — | SSH 密码（仅远程） |
| `--key <path>` | — | SSH 私钥路径（仅远程） |
| `--ssh-port <n>` | 22 | SSH 端口（仅远程） |

## 部署示例

### 激活企业版许可证

```
/setup-gitlab activate
```

激活流程：容器内生成密钥对和许可证 → 复制到宿主机并挂载公钥 → 重启容器 → Rails console 导入许可证。


### 远程部署（密码认证）

```
/setup-gitlab start --host <HOST> --user ubuntu --password mypassword
```

### 远程部署（私钥认证）

```
/setup-gitlab start --host <HOST> --user ubuntu --key ~/.ssh/id_rsa
```

### 远程激活许可证

```
/setup-gitlab activate --host <HOST> --user ubuntu --key ~/.ssh/id_rsa
```

### 查看远程状态

```
/setup-gitlab status --host <HOST> --user ubuntu --key ~/.ssh/id_rsa
```

## 目录说明

| 模式 | 工作目录 |
|------|---------|
| 远程 | `/opt/tech-stack/gitlab/` |

数据子目录：

| 子目录 | 用途 |
|--------|------|
| `config/` | GitLab 配置文件（**gitlab.rb 持久化位置**） |
| `logs/` | GitLab 日志文件 |
| `data/` | GitLab 数据存储（仓库、数据库等） |
| `license/` | 许可证文件（密钥对 + 许可证） |

## 配置管理

### 配置文件位置

| 宿主机路径 | 容器内路径 | 用途 |
|-----------|-----------|------|
| `./config/gitlab.rb` | `/etc/gitlab/gitlab.rb` | 主配置文件（唯一应修改） |
| `./config/gitlab-secrets.json` | `/etc/gitlab/gitlab-secrets.json` | 密钥存储（不要修改） |
| `./data/` | `/var/opt/gitlab/` | 运行时数据（会被 reconfigure 覆盖） |

### 修改配置流程

```bash
# 1. 编辑配置文件
vi /opt/tech-stack/gitlab/config/gitlab.rb

# 2. 应用配置（约 1-2 分钟）
docker exec tech-gitlab gitlab-ctl reconfigure

# 3. 如需重启服务
docker exec tech-gitlab gitlab-ctl restart
```

### 配置分工

| 配置来源 | 用途 | 示例 |
|---------|------|------|
| `.env` | Docker Compose 变量（端口、内存） | `GITLAB_HTTP_PORT=8929` |
| `gitlab.rb` | 所有 GitLab 配置 | `external_url`、`time_zone` 等 |

首次部署时，脚本会用 `envsubst` 从 `conf/gitlab.rb.tpl` 和 `.env` 渲染生成 `config/gitlab.rb`，仅替换 `${GITLAB_HOSTNAME}` 和 `${GITLAB_SSH_PORT}` 两个占位符，避免污染 Ruby 脚本中其他 `$` 开头变量。

### 常用配置示例

```ruby
# 禁用公开注册
gitlab_rails['gitlab_signup_enabled'] = false

# 配置 SMTP
gitlab_rails['smtp_enable'] = true
gitlab_rails['smtp_address'] = "smtp.example.com"
gitlab_rails['smtp_port'] = 587
gitlab_rails['smtp_user_name'] = "noreply@example.com"
gitlab_rails['smtp_password'] = "your_password"

# 配置备份
gitlab_rails['backup_keep_time'] = 604800
```

## 端口说明

| 端口 | 协议 | 用途 |
|------|------|------|
| 8929 | HTTP | Web 访问 |
| 8443 | HTTPS | Web 访问（SSL） |
| 2222 | SSH | Git SSH 操作 |

端口可通过 `.env` 中的 `GITLAB_HTTP_PORT`、`GITLAB_HTTPS_PORT`、`GITLAB_SSH_PORT` 自定义。其中 `GITLAB_SSH_PORT` 会在首次部署时自动同步到 `gitlab.rb` 中。

## SSH Clone 配置

```
Host <GITLAB_HOSTNAME>
  HostName <GITLAB_HOSTNAME>
  User git
  Port 2222
  IdentityFile ~/.ssh/id_rsa
```

克隆示例：

```bash
git clone ssh://git@<GITLAB_HOSTNAME>:2222/<namespace>/<repo>.git
```

## 许可证激活说明

### 激活原理

1. 在 GitLab 容器内生成 RSA 密钥对和许可证文件
2. 将公钥复制到宿主机并通过 volume 挂载到容器
3. 重启容器使新公钥生效
4. 通过 Rails console 导入许可证

> **关键**：必须在容器内生成许可证，确保公钥/私钥/许可证三者匹配。API 上传可能失败，推荐使用 Rails console。

### 许可证参数

| 参数 | 值 |
|------|--------|
| 计划 | Ultimate（必须显式指定） |
| 有效期 | 2025-01-01 ~ 2055-01-01 |
| 用户数 | 10,000 |

> **注意**：Epic 功能位于 **Group 级别**（非 Project 级别）。

### 持久化

公钥通过 volume mount 持久化：

```yaml
- ./license/license_key.pub:/opt/gitlab/.../.license_encryption_key.pub:ro
```

以下场景无需重新激活：容器重建、镜像升级、宿主机重启。

### 手动激活

如自动导入失败，可通过 Web UI 上传：

1. 登录 GitLab 管理后台
2. **Admin → Settings → General → Add License**
3. 上传 `license/GitLabBV.gitlab-license`

## 注意事项

- **资源消耗**：GitLab EE 较重，建议宿主机内存 4GB+，生产环境 8GB+
- **首次启动**：约需 3-5 分钟完成初始化，请耐心等待
- **SSH 端口**：GitLab SSH 使用 2222 而非 22，克隆时需指定端口
- **数据持久化**：删除 `data/` 目录将丢失所有仓库和数据库数据
- **生产配置**：务必修改 `.env` 中的 `GITLAB_HOSTNAME`，并在 `docker-compose.yml` 的 SMTP 配置段填写真实邮件服务器信息
- **许可证保管**：`license/` 目录中的私钥文件请妥善保管，勿提交到公开仓库
- **用户管理**：默认禁用公开注册，账号由管理员统一分配。执行 `/setup-gitlab create-user` 查看创建方式

## 用户管理

GitLab 默认禁用公开注册（`gitlab_signup_enabled = false`），用户账号需由管理员创建。

### 创建用户方式

| 方式 | 适用场景 | 操作位置 |
|------|---------|---------|
| Web UI | 推荐，图形化操作 | Admin → Users → New user |
| API | 批量创建、自动化 | `POST /api/v4/users` |
| Rails Console | 快速单次操作 | `docker exec -it tech-gitlab gitlab-rails console` |

### 开放注册（可选）

如需开放公开注册，修改 `config/gitlab.rb`：

```ruby
gitlab_rails['gitlab_signup_enabled'] = true
```

然后应用配置：

```bash
docker exec tech-gitlab gitlab-ctl reconfigure
```

> **安全警告**：开放注册可能导致垃圾账号，建议仅在受信任环境中开放。

## 备份与恢复

### 创建备份

```bash
# 创建完整备份（包含仓库、数据库、配置）
docker exec tech-gitlab gitlab-backup create

# 备份文件位置
ls /opt/tech-stack/gitlab/data/backups/
```

### 恢复备份

```bash
# 1. 停止服务
docker exec tech-gitlab gitlab-ctl stop puma
docker exec tech-gitlab gitlab-ctl stop sidekiq

# 2. 恢复备份（指定备份文件时间戳）
docker exec tech-gitlab gitlab-backup restore BACKUP=1700000000_2024_11_15_17.8.0

# 3. 重启服务
docker exec tech-gitlab gitlab-ctl restart
```

> **重要**：恢复时 `gitlab-secrets.json` 必须与备份时一致，否则加密数据无法解密。

### 升级版本

```bash
# 1. 创建备份
docker exec tech-gitlab gitlab-backup create

# 2. 修改 docker-compose.yml 中的镜像版本
#    image: gitlab/gitlab-ee:17.9.0-ee.0

# 3. 重建容器
cd /opt/tech-stack/gitlab
docker compose down
docker compose up -d

# 4. 等待迁移完成（约 5-10 分钟）
docker logs -f tech-gitlab
```

> **注意**：跨大版本升级（如 16.x → 17.x）需查阅官方升级路径文档。许可证公钥挂载后升级无需重新激活。
