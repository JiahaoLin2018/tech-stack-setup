# action: start — 启动 Tempo

## 参数解析

> **B 类 `--env` 契约**：本 Skill 支持 `--env nonprod|prod`，默认 `nonprod`。传入其他值立即报错退出。

```
ENV = 从调用参数解析 --env 的值，默认 nonprod
若 ENV ∉ {nonprod, prod} → 打印以下错误并终止执行：
  "ERROR: --env 参数只接受 nonprod 或 prod，当前值: <VALUE>"
```

以下所有步骤中的变量含义：
- `${ENV}` = nonprod 或 prod
- `REMOTE_DIR` = `/opt/tech-stack/tempo-${ENV}/`
- 容器名 = `tech-tempo-${ENV}`
- 数据接入域名（OTel Collector 推送）：`tempo-${ENV}.renew.com:14317`（OTLP gRPC）/ `:14318`（OTLP HTTP）
- 查询 API 域名（Grafana 查询）：`tempo-${ENV}.renew.com:3200`（直连数据端口）

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
REMOTE_DIR=/opt/tech-stack/tempo-${ENV}
SKILL_DIR="${CLAUDE_SKILL_DIR}"

ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  mkdir -p $REMOTE_DIR/data/tempo
  mkdir -p $REMOTE_DIR/conf
"

scp [AUTH_OPTIONS] -P <SSH_PORT> "$SKILL_DIR/references/docker-compose.yml" <SSH_USER>@<HOST>:$REMOTE_DIR/
scp [AUTH_OPTIONS] -P <SSH_PORT> "$SKILL_DIR/references/.env.example" <SSH_USER>@<HOST>:$REMOTE_DIR/.env
scp [AUTH_OPTIONS] -P <SSH_PORT> "$SKILL_DIR/references/conf/tempo-config.yml.tpl" \
    <SSH_USER>@<HOST>:$REMOTE_DIR/conf/
```

### 步骤 4：提示配置并等待确认

```
请在远程主机上修改配置：
  ssh <SSH_USER>@<HOST>
  vim /opt/tech-stack/tempo-${ENV}/.env
  （确认端口、资源限制和 PROMETHEUS_HOST 配置后保存退出）

修改完成后告知我，继续启动。
```

**等待用户确认后再继续后续步骤。**

### 步骤 5：远程渲染配置并设置权限

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  # 检查 envsubst 是否可用
  if ! command -v envsubst &>/dev/null; then
    echo 'envsubst 未安装，请先安装: sudo apt-get install -y gettext-base (或 yum install -y gettext)'
    exit 1
  fi
  cd /opt/tech-stack/tempo-${ENV}
  sed -i \"s|^ENV=.*|ENV=${ENV}|\" .env
  sed -i \"s|-nonprod\.renew\.com|-${ENV}.renew.com|g\" .env
  set -a && source .env && set +a
  envsubst '\${PROMETHEUS_HOST} \${PROMETHEUS_PORT} \${TEMPO_RETENTION}' < conf/tempo-config.yml.tpl > conf/tempo-config.yml
  chown -R 10001:10001 /opt/tech-stack/tempo-${ENV}/data/tempo 2>/dev/null \
    || chmod -R 777 /opt/tech-stack/tempo-${ENV}/data/tempo
"
```

### 步骤 6：远程启动

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  cd /opt/tech-stack/tempo-${ENV}
  docker compose up -d
"
```

### 步骤 7：等待远程 Tempo 健康

```bash
HTTP_PORT=$(ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "grep '^TEMPO_HTTP_PORT=' /opt/tech-stack/tempo-${ENV}/.env | cut -d= -f2")
HTTP_PORT=${HTTP_PORT:-3200}
for i in $(seq 1 12); do
  STATUS=$(ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> \
    "wget --no-verbose --tries=1 --spider http://localhost:${HTTP_PORT}/ready 2>/dev/null && echo HEALTHY || echo WAITING")
  [ "$STATUS" = "HEALTHY" ] && break
  echo "等待远程 Tempo 启动... (${i}/12)"
  sleep 15
done
```

### 步骤 8：展示远程访问信息

```
远程 Tempo（${ENV}）已启动！（请确认防火墙已放行对应端口）

  查询 API:     http://<HOST>:3200   (域名: tempo-${ENV}.renew.com:3200，写入 hosts.lan，Grafana 查询入口)
  OTLP gRPC:    <HOST>:14317         (域名: tempo-${ENV}.renew.com:14317，OTel Collector 推送 Traces 入口)
  OTLP HTTP:    http://<HOST>:14318  (域名: tempo-${ENV}.renew.com:14318，OTel Collector 推送 Traces 入口)
  Zipkin:       http://<HOST>:9411

Metrics Generator → Prometheus remote_write:
  目标: http://prometheus-${ENV}.renew.com:9090/api/v1/write
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
