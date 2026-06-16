# action: start — 启动 Loki 日志聚合服务

## 参数解析

> **B 类 `--env` 契约**：本 Skill 支持 `--env nonprod|prod`，默认 `nonprod`。传入其他值立即报错退出。

```
ENV = 从调用参数解析 --env 的值，默认 nonprod
若 ENV ∉ {nonprod, prod} → 打印以下错误并终止执行：
  "ERROR: --env 参数只接受 nonprod 或 prod，当前值: <VALUE>"
```

以下所有步骤中的变量含义：
- `${ENV}` = nonprod 或 prod
- `REMOTE_DIR` = `/opt/tech-stack/loki-${ENV}/`
- 容器名 = `tech-loki-${ENV}`
- 直连数据域名：`loki-${ENV}.renew.com:3100`（写入 hosts.lan，OTel Collector 推送 + Grafana 查询入口）

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
REMOTE_DIR=/opt/tech-stack/loki-${ENV}
SKILL_DIR="${CLAUDE_SKILL_DIR}"

ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  mkdir -p $REMOTE_DIR/data/loki
  mkdir -p $REMOTE_DIR/conf
  chown -R 10001:10001 $REMOTE_DIR/data/loki
  chmod -R 755 $REMOTE_DIR/data/loki
"

# 仅在目标文件不存在时上传 docker-compose.yml 和 .env，避免覆盖已有配置
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "[ ! -f $REMOTE_DIR/docker-compose.yml ]" && \
  scp [AUTH_OPTIONS] -P <SSH_PORT> "$SKILL_DIR/references/docker-compose.yml" <SSH_USER>@<HOST>:$REMOTE_DIR/
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "[ ! -f $REMOTE_DIR/.env ]" && \
  scp [AUTH_OPTIONS] -P <SSH_PORT> "$SKILL_DIR/references/.env.example" <SSH_USER>@<HOST>:$REMOTE_DIR/.env

# 每次上传模板文件（确保渲染幂等）
scp [AUTH_OPTIONS] -P <SSH_PORT> "$SKILL_DIR/references/conf/loki-config.yml.tpl" \
    <SSH_USER>@<HOST>:$REMOTE_DIR/conf/
```

### 步骤 4：提示配置并等待确认

```
请在远程主机上修改配置：
  ssh <SSH_USER>@<HOST>
  vim /opt/tech-stack/loki-${ENV}/.env
  （确认 ENV、ALERTMANAGER_HOST、端口、内存限制等配置后保存退出）
  ALERTMANAGER_HOST 应设为: alertmanager-${ENV}.renew.com

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
  cd /opt/tech-stack/loki-${ENV}
  sed -i \"s|^ENV=.*|ENV=${ENV}|\" .env
  sed -i \"s|-nonprod\.renew\.com|-${ENV}.renew.com|g\" .env
  set -a && source .env && set +a
  envsubst '\${ALERTMANAGER_HOST} \${ALERTMANAGER_PORT} \${LOKI_AUTH_ENABLED} \${LOKI_CACHE_MAX_SIZE_MB} \${LOKI_COMPACTION_INTERVAL} \${LOKI_GRPC_PORT} \${LOKI_INGESTION_BURST_SIZE_MB} \${LOKI_INGESTION_RATE_MB} \${LOKI_LOG_LEVEL} \${LOKI_MAX_QUERY_SERIES} \${LOKI_MAX_STREAMS_PER_USER} \${LOKI_RETENTION_DELETE_DELAY} \${LOKI_RETENTION_PERIOD}' < conf/loki-config.yml.tpl > conf/loki-config.yml
  chown -R 10001:10001 /opt/tech-stack/loki-${ENV}/data/loki 2>/dev/null \
    || chmod -R 777 /opt/tech-stack/loki-${ENV}/data/loki
"
```

### 步骤 6：远程启动

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  cd /opt/tech-stack/loki-${ENV}
  docker compose up -d
"
```

### 步骤 7：等待远程 Loki 健康

```bash
for i in $(seq 1 12); do
  STATUS=$(ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> \
    "if wget -q --spider http://localhost:3100/ready 2>/dev/null || \
        curl -sf http://localhost:3100/ready > /dev/null 2>&1; then \
       echo HEALTHY; \
     else \
       echo WAITING; \
     fi")
  [ "$STATUS" = "HEALTHY" ] && break
  echo "等待远程 Loki 启动... (${i}/12)"
  sleep 15
done
```

### 步骤 8：展示远程访问信息

```
远程 Loki（${ENV}）日志聚合服务已启动！（请确认防火墙已放行对应端口）

  Loki API（直连）: http://<HOST>:3100   (域名: loki-${ENV}.renew.com:3100，写入 hosts.lan)
  OTLP 推送端点:    http://loki-${ENV}.renew.com:3100/otlp   (OTel Collector 日志推送入口)
  Ready 检查:       http://<HOST>:3100/ready
  Metrics:          http://<HOST>:3100/metrics

  env 标签隔离：Pod 通过 OTEL_RESOURCE_ATTRIBUTES=deployment.environment={env} 注入，
  Loki 通过 otlp_config.resource_attributes 自动索引为 deployment_environment 标签
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
