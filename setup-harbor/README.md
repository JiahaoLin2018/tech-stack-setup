# setup-harbor — 入门指引

使用官方安装器部署 Harbor 私有 Docker 镜像仓库，支持本地和远程两种部署模式，含 Trivy 镜像漏洞扫描。

## 安装教程

在项目根目录下运行：

```bash
bash setup-harbor/install.sh
```

脚本会将 `setup-harbor/` 全部内容复制到 `~/.claude/skills/setup-harbor/`。

## 目录结构

```
setup-harbor/
├── SKILL.md                    # Skill 路由指令（Claude 读取）
├── README.md                   # 入门指引（人类读取）
├── install.sh                  # 安装脚本
├── actions/
│   ├── start.md                # 安装并启动流程（含本地/远程模式）
│   ├── stop.md                 # 停止流程
│   ├── status.md               # 状态查看
│   ├── verify.md               # 服务验证（含 docker login 测试）
│   └── logs.md                 # 日志查看
├── references/
│   ├── .env.example            # 环境变量模板
│   ├── pitfalls.md             # 踩坑记录
│   └── conf/
│       └── harbor.yml.tpl      # Harbor 配置模板（envsubst 渲染）
└── cache/                      # 本地缓存（安装包下载）
    └── harbor-offline-installer-*.tgz
```

## 用法

```
/setup-harbor [action] [选项]
```

### 参数说明

| 参数 | 说明 |
|------|------|
| `start`（默认） | 安装并启动 Harbor（含引导配置） |
| `stop` | 停止 Harbor |
| `status` | 查看所有服务状态 |
| `verify` | 验证服务健康（HTTP + Registry API + docker login） |
| `logs` | 查看 Harbor 日志 |

### 选项说明

| 选项 | 默认值 | 说明 |
|------|--------|------|
| `--host <ip>` | localhost | 部署目标 IP 或域名 |
| `--user <user>` | root | SSH 用户名（仅远程） |
| `--password <pass>` | — | SSH 密码（仅远程） |
| `--key <path>` | — | SSH 私钥路径（仅远程） |
| `--ssh-port <n>` | 22 | SSH 端口（仅远程） |

## 部署示例

### 远程部署（私钥认证）

```
/setup-harbor start --host <HOST> --user ubuntu --key ~/.ssh/id_rsa
```

### 查看远程状态

```
/setup-harbor status --host <HOST> --user ubuntu --key ~/.ssh/id_rsa
```

## 目录说明

| 模式 | 工作目录 |
|------|---------|
| 远程 | `/opt/tech-stack/harbor/` |

Harbor 实际安装目录（解压后）：`<工作目录>/harbor/`

## harbor.yml 关键配置项

| 配置项 | 说明 | 注意 |
|--------|------|------|
| `hostname` | `harbor.renew.com` | 项目统一域名（来自 `.env` 中 `HARBOR_HOSTNAME`） |
| `http.port` | HTTP 访问端口 | 默认 8880（为 infra-nginx 让出 :80） |
| `https` | HTTPS 配置段 | 测试环境可注释掉 |
| `harbor_admin_password` | 管理员初始密码 | 至少 8 位，含大小写和数字，对应 .env 中 `HARBOR_ADMIN_PASSWORD` |
| `database.password` | 数据库密码 | 生产必须修改，对应 .env 中 `HARBOR_DB_PASSWORD` |
| `data_volume` | 数据存储路径 | 确保磁盘空间充足（建议 50GB+） |

## 配置 insecure-registries（HTTP 模式）

若使用 HTTP 而非 HTTPS，Docker 客户端需配置白名单。编辑 `/etc/docker/daemon.json`（Linux）或 Docker Desktop 设置（Windows/Mac）：

```json
{
  "insecure-registries": ["harbor.renew.com"]
}
```

修改后重启 Docker：

```bash
# Linux
sudo systemctl restart docker

# Windows/Mac：重启 Docker Desktop
```

## 使用 Harbor

### 登录

```bash
docker login harbor.renew.com
# Username: admin
# Password: <harbor_admin_password>
```

### 推送镜像

```bash
# 为镜像打标签
docker tag myapp:latest harbor.renew.com/library/myapp:latest

# 推送
docker push harbor.renew.com/library/myapp:latest
```

### 拉取镜像

```bash
docker pull harbor.renew.com/library/myapp:latest
```

## 注意事项

- **hostname 固定为 `harbor.renew.com`**：通过 `.env` 中 `HARBOR_HOSTNAME` 渲染到 `harbor.yml`，确保跨机器可访问
- **Harbor 版本**：默认使用 v2.12.0 离线安装包，如需其他版本修改 .env 中的 HARBOR_VERSION
- **离线安装包**：需手动下载，访问 https://github.com/goharbor/harbor/releases
- **Trivy 漏洞扫描**：安装时通过 `--with-trivy` 启用，首次使用时需下载漏洞数据库
- **数据持久化**：数据存储于 harbor.yml 中 `data_volume` 指定路径，默认 `/opt/harbor-data`
- **防火墙**：确保 80（和/或 443）端口对目标机器可访问
