# action: start — 启动 Grafana

## 参数解析

> **B 类 `--env` 契约**：本 Skill 支持 `--env nonprod|prod`，默认 `nonprod`。传入其他值立即报错退出。

```
ENV = 从调用参数解析 --env 的值，默认 nonprod
若 ENV ∉ {nonprod, prod} → 打印以下错误并终止执行：
  "ERROR: --env 参数只接受 nonprod 或 prod，当前值: <VALUE>"
```

以下所有步骤中的变量含义：
- `${ENV}` = nonprod 或 prod
- `REMOTE_DIR` = `/opt/tech-stack/grafana-${ENV}/`
- 容器名 = `tech-grafana-${ENV}`
- Web UI 域名：`grafana-${ENV}-ui.renew.com`（infra-nginx 反代 → :3000，不写 hosts.lan）
- 数据源域名：`prometheus-${ENV}.renew.com:9090` / `tempo-${ENV}.renew.com:3200` / `loki-${ENV}.renew.com:3100`

## 步骤

> **文件上传约束**：上传 docker-compose.yml 等含 `${VAR}` 变量引用的文件时，必须使用文件复制方式（`scp` 或 `sftp.put()`），禁止使用 Python 字符串写入（会导致 `${VAR}` 被吞掉变为空值）。详见 `references/deployment-principles.md` 前置准备第 6 节。

### 步骤 1：建立 SSH 连接并验证

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "echo SSH_OK"
```

### 步骤 2：检查远程 Docker

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "docker info > /dev/null 2>&1 && echo RUNNING || echo NOT_RUNNING"
```

### 步骤 3：上传配置到远程主机

```bash
REMOTE_DIR=/opt/tech-stack/grafana-${ENV}
SKILL_DIR="${CLAUDE_SKILL_DIR}"

ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  mkdir -p $REMOTE_DIR/data/grafana
  mkdir -p $REMOTE_DIR/conf/grafana/provisioning/datasources
  mkdir -p $REMOTE_DIR/conf/grafana/provisioning/dashboards
  chmod 777 $REMOTE_DIR/data/grafana
"

scp [AUTH_OPTIONS] -P <SSH_PORT> "$SKILL_DIR/references/docker-compose.yml" <SSH_USER>@<HOST>:$REMOTE_DIR/

# .env 仅在不存在时上传，不覆盖已有配置
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "test -f $REMOTE_DIR/.env && echo EXISTS || echo NOT_EXISTS"
# NOT_EXISTS → 上传模板
scp [AUTH_OPTIONS] -P <SSH_PORT> "$SKILL_DIR/references/.env.example" <SSH_USER>@<HOST>:$REMOTE_DIR/.env
# EXISTS → 跳过，保留用户已修改的配置

# 每次上传模板文件（确保渲染幂等）
scp [AUTH_OPTIONS] -P <SSH_PORT> "$SKILL_DIR/references/conf/grafana/provisioning/datasources/datasources.yml.tpl" \
    <SSH_USER>@<HOST>:$REMOTE_DIR/conf/grafana/provisioning/datasources/
scp [AUTH_OPTIONS] -P <SSH_PORT> "$SKILL_DIR/references/conf/grafana/provisioning/dashboards/dashboards.yml" \
    <SSH_USER>@<HOST>:$REMOTE_DIR/conf/grafana/provisioning/dashboards/
```

### 步骤 4：校验密码占位符并提示配置

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "grep -q 'CHANGE_ME' $REMOTE_DIR/.env && echo HAS_PLACEHOLDER || echo OK"
```

- `HAS_PLACEHOLDER` → 提示用户修改密码并等待确认：

```
请在远程主机上修改配置：
  ssh <SSH_USER>@<HOST>
  vim /opt/tech-stack/grafana-${ENV}/.env
  （修改 GRAFANA_ADMIN_PASSWORD，去除所有 CHANGE_ME 占位符后保存退出）
  确认数据源域名：
    PROMETHEUS_HOST=prometheus-${ENV}.renew.com
    TEMPO_HOST=tempo-${ENV}.renew.com
    LOKI_HOST=loki-${ENV}.renew.com
    GRAFANA_ROOT_URL=http://grafana-${ENV}-ui.renew.com

修改完成后告知我，继续启动。
```

- `OK` → 继续

**等待用户确认后再继续后续步骤。**

### 步骤 5：远程渲染配置

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  # 检查 envsubst 是否可用
  if ! command -v envsubst &>/dev/null; then
    echo 'envsubst 未安装，请先安装: sudo apt-get install -y gettext-base (或 yum install -y gettext)'
    exit 1
  fi
  cd /opt/tech-stack/grafana-${ENV}
  sed -i \"s|^ENV=.*|ENV=${ENV}|\" .env
  sed -i \"s|-nonprod\.renew\.com|-${ENV}.renew.com|g\" .env
  set -a && source .env && set +a
  envsubst '\${PROMETHEUS_HOST} \${PROMETHEUS_PORT} \${TEMPO_HOST} \${TEMPO_PORT} \${LOKI_HOST} \${LOKI_PORT}' < conf/grafana/provisioning/datasources/datasources.yml.tpl > conf/grafana/provisioning/datasources/datasources.yml
  echo 'datasources.yml 渲染完成'
"
```

### 步骤 6：远程启动

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  cd /opt/tech-stack/grafana-${ENV}
  docker compose up -d
"
```

### 步骤 7：等待远程 Grafana 健康

```bash
for i in $(seq 1 12); do
  STATUS=$(ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> \
    "curl -sf http://localhost:3000/api/health 2>/dev/null && echo HEALTHY || echo WAITING")
  [ "$STATUS" = "HEALTHY" ] && break
  echo "等待远程 Grafana 启动... (${i}/12)"
  sleep 10
done
```

### 步骤 8：展示远程访问信息

```
远程 Grafana（${ENV}）已启动！

  Web UI（通过 infra-nginx 反代）: http://grafana-${ENV}-ui.renew.com
  直接端口访问: http://<HOST>:3000   (admin / <GRAFANA_ADMIN_PASSWORD>)

  数据源连接（② 域级直连，须在 hosts.lan 中配置）：
    Prometheus: http://prometheus-${ENV}.renew.com:9090
    Tempo:      http://tempo-${ENV}.renew.com:3200
    Loki:       http://loki-${ENV}.renew.com:3100
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
