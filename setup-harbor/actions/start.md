# action: start — 安装并启动 Harbor

Harbor 使用官方安装器（`./install.sh`）部署，而非手动编写 docker-compose。

---

## 步骤

> **文件上传约束**：上传 docker-compose.yml 等含 `${VAR}` 变量引用的文件时，必须使用文件复制方式（`scp` 或 `sftp.put()`），禁止使用 Python 字符串写入（会导致 `${VAR}` 被吞掉变为空值）。详见 `references/deployment-principles.md` 前置准备第 6 节。

### 前置检查：全局唯一服务拒绝 --env 参数

```bash
# 本 skill 为 C 类全局唯一服务，不接受 --env 参数
if [ -n "${ENV}" ]; then
  echo "ERROR: setup-harbor is a global-unique service and does not accept --env"
  exit 1
fi
```

若用户传入了 `--env` 参数，立即报错退出，不继续执行后续步骤。

### 步骤 1：测试 SSH 连通性

```bash
ssh [AUTH_OPTS] -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p <SSH_PORT> <SSH_USER>@<HOST> "echo SSH连接成功"
```

若连接失败，报告错误并终止流程。

### 步骤 2：检查远程 Docker 和 Docker Compose

```bash
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "docker info > /dev/null 2>&1 && echo 'Docker OK' || echo 'Docker FAIL'"
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "docker-compose version 2>/dev/null || docker compose version 2>/dev/null || echo 'Compose FAIL'"
```

### 步骤 3：准备远程部署目录

```bash
REMOTE_DIR="/opt/tech-stack/harbor"
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> "mkdir -p $REMOTE_DIR"
echo "远程目录已就绪：$REMOTE_DIR"
```

### 步骤 4：上传配置文件

> **说明**：Harbor 使用 `harbor.yml` 作为配置文件，不使用 `.env`。`.env` 文件仅作为参数记录，方便查看和管理密码、版本等信息。

```bash
SKILL_REFS="${CLAUDE_SKILL_DIR}/references"
SCP_OPTS="-o StrictHostKeyChecking=no -P <SSH_PORT>"
# 若使用私钥：SCP_OPTS="$SCP_OPTS -i <KEY_PATH>"

# 上传 .env 作为参数记录（若远程尚无 .env）
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> "[ -f $REMOTE_DIR/.env ]" || \
  scp $SCP_OPTS "$SKILL_REFS/.env.example" <SSH_USER>@<HOST>:$REMOTE_DIR/.env

# 创建配置目录并上传 harbor.yml 模板
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> "mkdir -p $REMOTE_DIR/conf"
scp $SCP_OPTS "$SKILL_REFS/conf/harbor.yml.tpl" <SSH_USER>@<HOST>:$REMOTE_DIR/conf/
echo "配置文件已上传到 $REMOTE_DIR/"
```

### 步骤 5：手工下载并上传 Harbor 安装包

> **重要**：Harbor 离线安装包约 640MB，远程服务器通常无法直接访问 GitHub。**必须手工下载后上传到远程服务器**。

#### 5.1 检查远程是否已有安装包

```bash
REMOTE_ENV=$(ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> "cat $REMOTE_DIR/.env 2>/dev/null")
HARBOR_VERSION=$(echo "$REMOTE_ENV" | grep HARBOR_VERSION | cut -d= -f2 || echo "v2.12.0")
INSTALLER="harbor-offline-installer-${HARBOR_VERSION}.tgz"

HAS_INSTALLER=$(ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "[ -f $REMOTE_DIR/$INSTALLER ] && echo YES || ([ -d $REMOTE_DIR/harbor ] && echo EXTRACTED || echo NO)")
```

- 若 `YES` 或 `EXTRACTED`：跳到步骤 6
- 若 `NO`：提示用户手工下载并上传

#### 5.2 手工下载安装包

**下载地址**：https://github.com/goharbor/harbor/releases/download/v2.12.0/harbor-offline-installer-v2.12.0.tgz

> 也可以从其他镜像源下载，确保文件大小约 637MB。

#### 5.3 上传到远程服务器

**方式一：使用 scp 命令**

```bash
# 本地文件路径（根据实际下载位置调整）
LOCAL_FILE="/path/to/harbor-offline-installer-v2.12.0.tgz"

# 上传到远程服务器
scp -P <SSH_PORT> "$LOCAL_FILE" <SSH_USER>@<HOST>:/opt/tech-stack/harbor/
```

**方式二：使用 Python SFTP 上传**

```python
import paramiko
import os

HOST = "<HOST>"
SSH_PORT = <SSH_PORT>
SSH_USER = "<SSH_USER>"
SSH_PASSWORD = "<SSH_PASSWORD>"  # 或使用密钥
REMOTE_DIR = "/opt/tech-stack/harbor"
LOCAL_FILE = "/path/to/harbor-offline-installer-v2.12.0.tgz"  # 用户指定的本地文件路径

# 检查本地文件
if not os.path.exists(LOCAL_FILE):
    print(f"[错误] 文件不存在: {LOCAL_FILE}")
    print(f"请先下载 Harbor 安装包: https://github.com/goharbor/harbor/releases/download/v2.12.0/harbor-offline-installer-v2.12.0.tgz")
    exit(1)

local_size = os.path.getsize(LOCAL_FILE)
print(f"本地文件: {LOCAL_FILE}")
print(f"文件大小: {local_size / 1024 / 1024:.1f} MB")

if local_size < 600 * 1024 * 1024:  # 小于 600MB 可能不完整
    print(f"[警告] 文件可能不完整，期望大小约 637MB")

# 连接并上传
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(HOST, port=SSH_PORT, username=SSH_USER, password=SSH_PASSWORD)

sftp = ssh.open_sftp()
remote_path = f"{REMOTE_DIR}/harbor-offline-installer-v2.12.0.tgz"

print(f"上传中...")
sftp.put(LOCAL_FILE, remote_path)
print(f"上传完成: {remote_path}")

sftp.close()
ssh.close()
```

#### 5.4 验证上传

```bash
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "ls -lh $REMOTE_DIR/harbor-offline-installer-*.tgz"
# 期望输出文件大小约 638M
```

### 步骤 6：解压安装包并生成配置

```bash
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  cd $REMOTE_DIR &&

  # 解压安装包（若尚未解压）
  if [ ! -d harbor ]; then
    tar xzf harbor-offline-installer-*.tgz
  fi

  # 导出 .env 变量并生成 harbor.yml
  set -a && source .env && set +a
  envsubst '\${HARBOR_ADMIN_PASSWORD} \${HARBOR_DATA_DIR} \${HARBOR_DB_PASSWORD} \${HARBOR_HOSTNAME} \${HARBOR_HTTPS_PORT} \${HARBOR_HTTP_PORT}' < conf/harbor.yml.tpl > harbor/harbor.yml
"
```

**变量映射**：

| harbor.yml.tpl 占位符 | .env 变量 |
|----------------------|----------|
| `${HARBOR_HOSTNAME}` | Harbor 访问域名 |
| `${HARBOR_HTTP_PORT}` | HTTP 端口 |
| `${HARBOR_ADMIN_PASSWORD}` | 管理员密码 |
| `${HARBOR_DB_PASSWORD}` | 数据库密码 |
| `${HARBOR_DATA_DIR}` | 数据存储目录 |

### 步骤 7：远程执行安装

```bash
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "cd $REMOTE_DIR/harbor && ./install.sh --with-trivy"
echo "Harbor 安装完成"
```

安装过程约 2-5 分钟，输出示例：
```
[Step 0]: checking if docker is installed ...
[Step 1]: checking docker-compose is installed ...
[Step 2]: loading Harbor images ...
[Step 3]: preparing environment ...
[Step 4]: preparing harbor configs ...
[Step 5]: starting harbor ...
✔ ----Harbor has been installed and started successfully.----
```

### 步骤 8：验证部署

```bash
# 检查容器状态
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "docker ps --filter 'name=harbor' --format 'table {{.Names}}\t{{.Status}}'"

# 检查端口
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "ss -tlnp | grep <HARBOR_HTTP_PORT>"

# 验证 API 响应
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "curl -sf http://127.0.0.1:<HARBOR_HTTP_PORT>/api/v2.0/systeminfo"
```

### 步骤 9：展示远程访问信息

```
Harbor 已在远程服务器安装完成！

远程主机：<HOST>
访问地址：http://harbor.renew.com（via infra-nginx:80 → 宿主机:8880 → Harbor）
管理员账号：admin
管理员密码：<HARBOR_ADMIN_PASSWORD>

若使用 HTTP，在客户端 daemon.json 中添加 insecure-registries（统一使用域名，无端口）：
  { "insecure-registries": ["harbor.renew.com"] }

Docker 登录：
  docker login harbor.renew.com

若域名无法解析，请确认 dnsmasq 已部署并在本机配置 DNS 指向 dnsmasq 服务器。
```

---

## 部署报告输出

> 部署完成后，必须在项目 `env/` 目录下生成或更新该服务的部署报告文件 `env/<service>.md`。

报告模板：

```markdown
# <服务名称> — 部署报告

| 项目 | 值 |
|------|-----|
| 部署日期 | YYYY-MM-DD |
| 目标机器 | <IP> |
| 部署目录 | /opt/tech-stack/<service>/ |
| 版本 | <version> |

## 端口

| 端口 | 用途 |
|------|------|
| <port> | <description> |

## 账号密码

| 用户 | 密码 | 权限 | 允许来源 |
|------|------|------|---------|
| <user> | <password> | <permissions> | <access_scope> |

## 连接方式

| 方式 | 地址 |
|------|------|
| <client_type> | <connection_string> |

## 备注

- <部署过程中的特殊配置或踩坑记录>
```

报告文件路径：`<project_root>/env/<service>.md`（如 `env/harbor.md`）

---

## 故障排除

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| prepare 报错 KeyError | harbor.yml 缺少必需字段 | 使用完整的 `harbor.yml.tpl` 模板 |
| 安装包下载失败 | GitHub 国内访问受限 | 手工下载后使用 scp 上传 |
| 上传失败 | 磁盘空间不足 | 清理远程服务器磁盘空间 |
| install.sh 报错 | harbor.yml 配置错误 | 检查 hostname、密码等配置 |
| 容器启动失败 | 端口被占用 | 检查端口是否被占用 |
| 数据库连接失败 | 数据库密码不匹配 | 确保 harbor.yml 中密码与首次部署一致 |
