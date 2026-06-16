# action: start — 启动 Prometheus + Alertmanager

## 参数解析

> **B 类 `--env` 契约**：本 Skill 支持 `--env nonprod|prod`，默认 `nonprod`。传入其他值立即报错退出。

```
ENV = 从调用参数解析 --env 的值，默认 nonprod
若 ENV ∉ {nonprod, prod} → 打印以下错误并终止执行：
  "ERROR: --env 参数只接受 nonprod 或 prod，当前值: <VALUE>"
```

以下所有步骤中的变量含义：
- `${ENV}` = nonprod 或 prod
- `REMOTE_DIR` = `/opt/tech-stack/prometheus-${ENV}/`
- 容器名 = `tech-prometheus-${ENV}` / `tech-alertmanager-${ENV}`
- 直连数据域名：`prometheus-${ENV}.renew.com:9090`（写入 hosts.lan）
- Web UI 域名：`prometheus-${ENV}-ui.renew.com`（infra-nginx 反代，不写 hosts.lan）
- **prometheus.yml 模板选择**：nonprod → `prometheus.nonprod.yml`；prod → `prometheus.prod.yml`

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
REMOTE_DIR=/opt/tech-stack/prometheus-${ENV}
SKILL_DIR="${CLAUDE_SKILL_DIR}"

ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  mkdir -p $REMOTE_DIR/data/prometheus $REMOTE_DIR/data/alertmanager
  mkdir -p $REMOTE_DIR/conf/prometheus/rules
  mkdir -p $REMOTE_DIR/conf/alertmanager
"

# 仅在远程文件不存在时上传（不覆盖已有配置）
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "test -f $REMOTE_DIR/docker-compose.yml" \
  || scp [AUTH_OPTIONS] -P <SSH_PORT> "$SKILL_DIR/references/docker-compose.yml" <SSH_USER>@<HOST>:$REMOTE_DIR/
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "test -f $REMOTE_DIR/.env" \
  || scp [AUTH_OPTIONS] -P <SSH_PORT> "$SKILL_DIR/references/.env.example" <SSH_USER>@<HOST>:$REMOTE_DIR/.env

# 按 --env 选择对应的 prometheus.yml 模板（含多环境域名配置）
# nonprod → prometheus.nonprod.yml（4 套 consul_sd + 4 套 exporter，含 relabel env 标签）
# prod    → prometheus.prod.yml（1 套 consul_sd + 1 套 exporter）
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "test -f $REMOTE_DIR/conf/prometheus/prometheus.yml" \
  || scp [AUTH_OPTIONS] -P <SSH_PORT> "$SKILL_DIR/references/conf/prometheus/prometheus.${ENV}.yml" \
    <SSH_USER>@<HOST>:$REMOTE_DIR/conf/prometheus/prometheus.yml
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "test -f $REMOTE_DIR/conf/alertmanager/alertmanager.yml" \
  || scp [AUTH_OPTIONS] -P <SSH_PORT> "$SKILL_DIR/references/conf/alertmanager/alertmanager.yml" \
    <SSH_USER>@<HOST>:$REMOTE_DIR/conf/alertmanager/

# 上传告警规则文件（不覆盖已有规则）
for rule_file in "$SKILL_DIR/references/conf/prometheus/rules/"*.yml; do
  [ -f "$rule_file" ] || continue
  base=$(basename "$rule_file")
  ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "test -f $REMOTE_DIR/conf/prometheus/rules/$base" \
    || scp [AUTH_OPTIONS] -P <SSH_PORT> "$rule_file" <SSH_USER>@<HOST>:$REMOTE_DIR/conf/prometheus/rules/
done

# 强制对齐 .env 中 ENV 行与 --env 参数（防止默认 nonprod 在 prod 部署时残留致容器名错位）
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "sed -i 's|^ENV=.*|ENV=${ENV}|' $REMOTE_DIR/.env"
```

### 步骤 4：修正权限并检查 Consul 可达性

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  # 修正数据目录权限
  chmod -R 777 /opt/tech-stack/prometheus-${ENV}/data/prometheus
  chmod -R 777 /opt/tech-stack/prometheus-${ENV}/data/alertmanager
"
```

检查第一个 Consul 实例可达性（nonprod 检查 consul-dev，prod 检查 consul-prod）：

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  # nonprod 检查 consul-dev，prod 检查 consul-prod
  if [ '${ENV}' = 'prod' ]; then
    CONSUL_TARGET='consul-prod.renew.com:8500'
  else
    CONSUL_TARGET='consul-dev.renew.com:8500'
  fi
  curl -sf http://\${CONSUL_TARGET}/v1/status/leader > /dev/null 2>&1 \
    && echo CONSUL_REACHABLE || echo CONSUL_UNREACHABLE
"
```

- `CONSUL_REACHABLE` → 继续
- `CONSUL_UNREACHABLE` → 提示用户检查 DNS 配置和对应 Consul 是否已启动

### 步骤 5：远程启动

```bash
ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  cd /opt/tech-stack/prometheus-${ENV}
  docker compose up -d
"
```

### 步骤 6：等待远程服务健康

```bash
# 等待 Prometheus
for i in $(seq 1 12); do
  STATUS=$(ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> \
    "source /opt/tech-stack/prometheus-${ENV}/.env && curl -sf http://localhost:\${PROMETHEUS_PORT:-9090}/-/healthy 2>/dev/null && echo HEALTHY || echo WAITING")
  [ "$STATUS" = "HEALTHY" ] && break
  echo "等待远程 Prometheus 启动... (${i}/12)"
  sleep 10
done

# 等待 Alertmanager
for i in $(seq 1 6); do
  STATUS=$(ssh [AUTH_OPTIONS] -p <SSH_PORT> <SSH_USER>@<HOST> \
    "source /opt/tech-stack/prometheus-${ENV}/.env && curl -sf http://localhost:\${ALERTMANAGER_PORT:-9093}/-/healthy 2>/dev/null && echo HEALTHY || echo WAITING")
  [ "$STATUS" = "HEALTHY" ] && break
  echo "等待远程 Alertmanager 启动... (${i}/6)"
  sleep 5
done
```

### 步骤 7：展示远程访问信息

```
远程 Prometheus + Alertmanager（${ENV}）已启动！（请确认防火墙已放行对应端口）

  Prometheus 直连数据（写入 hosts.lan）: prometheus-${ENV}.renew.com:9090
  Prometheus Web UI（infra-nginx 反代）: http://prometheus-${ENV}-ui.renew.com
  Alertmanager Web UI（infra-nginx 反代）: http://alertmanager-${ENV}-ui.renew.com

  nonprod 采集目标：dev/sit/fat/uat 四套 consul_sd + exporter（含 env 标签）
  prod 采集目标：prod 单套 consul_sd + exporter（env=prod）

可视化面板：部署 /setup-grafana --env ${ENV} 获取统一可视化看板
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
