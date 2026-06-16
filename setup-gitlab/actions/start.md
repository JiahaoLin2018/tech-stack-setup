# action: start — 启动 GitLab

## 步骤

> **文件上传约束**：上传 docker-compose.yml 等含 `${VAR}` 变量引用的文件时，必须使用文件复制方式（`scp` 或 `sftp.put()`），禁止使用 Python 字符串写入（会导致 `${VAR}` 被吞掉变为空值）。详见 `references/deployment-principles.md` 前置准备第 6 节。

### 前置检查：全局唯一服务拒绝 --env 参数

```bash
# 本 skill 为 C 类全局唯一服务，不接受 --env 参数
if [ -n "${ENV}" ]; then
  echo "ERROR: setup-gitlab is a global-unique service and does not accept --env"
  exit 1
fi
```

若用户传入了 `--env` 参数，立即报错退出，不继续执行后续步骤。

### 步骤 1：测试 SSH 连通性

使用用户提供的 --host、--user、--password 或 --key、--ssh-port 参数：

```bash
# 使用密码
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p <SSH_PORT> <SSH_USER>@<HOST> "echo SSH连接成功"

# 使用私钥
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i <KEY_PATH> -p <SSH_PORT> <SSH_USER>@<HOST> "echo SSH连接成功"
```

若连接失败，报告错误信息并终止流程。

### 步骤 2：检查远程 Docker

```bash
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> "docker info > /dev/null 2>&1 && echo OK || echo FAIL"
```

若远程 Docker 未运行，提示用户在远程服务器启动 Docker，终止流程。

### 步骤 3：准备远程部署目录

```bash
REMOTE_DIR="/opt/tech-stack/gitlab"
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  mkdir -p $REMOTE_DIR/config $REMOTE_DIR/logs $REMOTE_DIR/data $REMOTE_DIR/license $REMOTE_DIR/conf
  # license_key.pub 由 /setup-gitlab activate 生成；首次启动占位空文件供 docker-compose 挂载
  touch $REMOTE_DIR/license/license_key.pub
"
echo "远程目录已就绪：$REMOTE_DIR"
```

### 步骤 4：上传配置文件

```bash
SKILL_REFS="${CLAUDE_SKILL_DIR}/references"
SCP_OPTS="-o StrictHostKeyChecking=no -P <SSH_PORT>"
# 若使用私钥：SCP_OPTS="$SCP_OPTS -i <KEY_PATH>"

scp $SCP_OPTS "$SKILL_REFS/docker-compose.yml" <SSH_USER>@<HOST>:$REMOTE_DIR/
echo "docker-compose.yml 已上传"

# 若远程尚无 .env，上传模板
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> "[ -f $REMOTE_DIR/.env ]" || \
  scp $SCP_OPTS "$SKILL_REFS/.env.example" <SSH_USER>@<HOST>:$REMOTE_DIR/.env
```

### 步骤 5：生成 gitlab.rb 配置文件

若远程尚无 `gitlab.rb`，使用 `envsubst` 从模板生成：

```bash
# 检查是否已存在 gitlab.rb
if ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> "[ ! -f $REMOTE_DIR/config/gitlab.rb ]"; then
  # 上传模板文件
  scp $SCP_OPTS "$SKILL_REFS/conf/gitlab.rb.tpl" <SSH_USER>@<HOST>:$REMOTE_DIR/conf/

  # 使用 envsubst 从 .env 生成配置文件
  ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> "
    cd $REMOTE_DIR && \
    set -a && source .env && set +a && \
    envsubst '\${GITLAB_HOSTNAME} \${GITLAB_SSH_PORT}' < conf/gitlab.rb.tpl > config/gitlab.rb
  "

  echo "gitlab.rb 已生成"
fi
```

> **说明**：`envsubst` 是 Linux 标准工具（gettext 包），会将 `${VAR}` 替换为对应环境变量的值。此方法比 `sed` 替换更健壮，不依赖硬编码字符串。

### 步骤 6：确认配置

```bash
echo "远程 .env 当前内容："
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> "cat $REMOTE_DIR/.env"

echo "远程 gitlab.rb 关键配置："
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "grep -E 'external_url|gitlab_shell_ssh_port' $REMOTE_DIR/config/gitlab.rb"
```

提示用户：若需修改配置，请编辑 `.env` 和 `gitlab.rb`，然后执行 `gitlab-ctl reconfigure`。

### 步骤 7：远程执行 docker compose up

```bash
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "cd /opt/tech-stack/gitlab && docker compose up -d"
echo "GitLab 容器已在远程服务器启动，首次启动约需 3-5 分钟..."
```

### 步骤 8：远程健康检查

```bash
for i in $(seq 1 10); do
  STATUS=$(ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
    "docker exec tech-gitlab gitlab-ctl status 2>/dev/null | grep -c 'run:' || echo 0")
  if [ "$STATUS" -gt 3 ]; then
    echo "GitLab 内部服务已就绪"
    break
  fi
  echo "等待远程服务启动... ($i/10)"
  sleep 30
done
```

### 步骤 9：展示远程访问信息

```
GitLab EE 已在远程服务器启动！

远程主机：<HOST>
访问地址：http://gitlab.renew.com（via infra-nginx:80 → 宿主机:8929 → 容器:80）
SSH Clone：ssh://git@gitlab.renew.com:2222/<namespace>/<repo>.git

首次登录：请访问上述 HTTP 地址设置 root 账号密码
许可证激活：首次部署需执行 /setup-gitlab activate 激活企业版许可证

若使用域名而非 IP，请确保 DNS 已指向 <HOST>
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
| 容器名称 | <container_name> |
| 镜像 | <image:tag> |
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

报告文件路径：`<project_root>/env/<service>.md`（如 `env/mysql.md`、`env/redis.md`）