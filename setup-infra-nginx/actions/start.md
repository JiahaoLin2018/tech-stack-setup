# action: start — 启动 infra-nginx

## 前置确认（必须执行）

> **重要**：在执行部署步骤前，必须先检查目标机器的服务和端口状态，与用户确认部署方案。

### 确认步骤

**1. 检查目标机器端口状态**

```python
import paramiko

def check_ports(host, user, password):
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(host, port=22, username=user, password=password)
    stdin, stdout, stderr = ssh.exec_command(
        "netstat -tlnp 2>/dev/null | grep -E ':80 |:2222 |:8082 ' || echo 'PORTS_AVAILABLE'"
    )
    result = stdout.read().decode()
    ssh.close()
    return result
```

**2. 检查跨机 upstream TCP 可达性**（从 .env 读取 HOST 变量，不硬编码 IP）

```python
import socket

def check_tcp(host, port, timeout=2):
    if not host or 'CHANGE_ME' in host:
        return 'UNCONFIGURED'
    try:
        with socket.create_connection((host, int(port)), timeout=timeout):
            return 'REACHABLE'
    except Exception:
        return 'UNREACHABLE'

def check_cross_machine_services(env_vars):
    port = int(env_vars.get('K3S_TRAEFIK_PORT', 8083))
    checks = [
        ('GitLab HTTP',        env_vars.get('GITLAB_HOST'),              int(env_vars.get('GITLAB_HTTP_PORT', 8929))),
        ('Nexus HTTP',         env_vars.get('NEXUS_HOST'),               int(env_vars.get('NEXUS_HTTP_PORT', 8081))),
        ('Harbor HTTP',        env_vars.get('HARBOR_HOST'),              int(env_vars.get('HARBOR_PORT', 8880))),
        ('Apollo Portal',      env_vars.get('APOLLO_HOST'),              int(env_vars.get('APOLLO_PORTAL_PORT', 8070))),
        ('Grafana nonprod',    env_vars.get('GRAFANA_NONPROD_HOST'),     3000),
        ('Prometheus nonprod', env_vars.get('PROMETHEUS_NONPROD_HOST'), 9090),
        ('K3s nonprod',        env_vars.get('K3S_NONPROD_TRAEFIK_HOST'), port),
        ('K3s prod',           env_vars.get('K3S_PROD_TRAEFIK_HOST'),    port),
    ]
    return [(name, host, port, check_tcp(host, port)) for name, host, port in checks]
```

> **不可达只警告不阻断**：upstream 不可达是预期场景（蓝图原则：infra-nginx 部署时预配置全部反代规则，upstream 未就绪时返回 502，不影响 nginx 自身运行）。

**3. 展示确认信息并询问用户**

```
=== 部署前检查 ===

目标机器: ${HOST}

端口状态（本机：infra-nginx 需占用）:
  :80   → ${PORT_80_STATUS}
  :2222 → ${PORT_2222_STATUS}
  :8082 → ${PORT_8082_STATUS}

跨机 upstream（来自 .env，仅 WARNING 不阻断）:
  GitLab      (${GITLAB_HOST}:${GITLAB_HTTP_PORT})              → ${GITLAB_STATUS}
  Nexus       (${NEXUS_HOST}:${NEXUS_HTTP_PORT})                → ${NEXUS_STATUS}
  Harbor      (${HARBOR_HOST}:${HARBOR_PORT})                   → ${HARBOR_STATUS}
  Apollo      (${APOLLO_HOST}:${APOLLO_PORTAL_PORT})            → ${APOLLO_STATUS}
  Grafana     (${GRAFANA_NONPROD_HOST}:3000)                    → ${GRAFANA_NONPROD_STATUS}
  Prometheus  (${PROMETHEUS_NONPROD_HOST}:9090)                 → ${PROM_NONPROD_STATUS}
  K3s nonprod (${K3S_NONPROD_TRAEFIK_HOST}:${K3S_TRAEFIK_PORT}) → ${K3S_NONPROD_STATUS}
  K3s prod    (${K3S_PROD_TRAEFIK_HOST}:${K3S_TRAEFIK_PORT})    → ${K3S_PROD_STATUS}
  ...

请确认部署方案:
  1. 继续部署（默认）
  2. 取消部署

请输入选项 (1-2):
```

**4. 处理用户选择**

| 选项 | 处理方式 |
|------|---------|
| 1 | 继续部署：本机端口 :80/:2222/:8082 任一被占即报错退出（属环境清理责任，由用户自行清理后重试） |
| 2 | 终止部署流程 |

> **干净服务器假设**：upstream 不可达仅记录 WARNING；本机端口占用应由用户先清理，skill 不主动 disable / kill / 重写系统配置；`.env` 是单一可信来源，skill 不反向修改。

---

## 部署步骤

> 前置确认完成后，执行以下步骤。

### 步骤 0：--env 参数校验（C 类：全局唯一，不接受）

```bash
if [ -n "$ENV" ]; then
  echo "❌ setup-infra-nginx 是全局唯一服务（C 类），不接受 --env 参数。"
  echo "   请移除 --env 参数后重试。"
  exit 1
fi
```

### 步骤 1：检查本地 SSH 工具

```bash
# 密码模式
which sshpass > /dev/null 2>&1 || echo "MISSING_SSHPASS"
# 密钥模式
ls ${SSH_KEY_PATH} 2>/dev/null || echo "MISSING_KEY"
```

- 缺少 sshpass（密码模式）→ 提示 `apt install sshpass` 或改用 `--key`
- 密钥文件不存在 → 提示检查路径

> **Windows 环境**：若 sshpass 不可用，使用 Python paramiko 库执行 SSH 操作。

### 步骤 2：测试 SSH 连接

```bash
# 密码模式
sshpass -p "${SSH_PASSWORD}" ssh -o StrictHostKeyChecking=no -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} "echo OK"
# 密钥模式
ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} "echo OK"
```

- 连接失败 → 报告错误信息，终止执行

### 步骤 3：本地替换变量后上传配置文件

> nginx 配置中的 `${VAR}` 由本地 Python 正则替换为 `.env` 实际值后再上传。详细原因见 `references/pitfalls.md`。

使用 Python 执行变量替换：

```python
import re

# 从 .env 文件读取所有变量（所有 HOST/PORT 均来自 .env，不硬编码 IP）
env_vars = {}
with open('.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, v = line.split('=', 1)
            env_vars[k.strip()] = v.strip()

# 检查必填变量
required_keys = [
    'GITLAB_HOST', 'NEXUS_HOST', 'HARBOR_HOST', 'DNS_HOST',
    'APOLLO_HOST', 'APOLLO_PROD_HOST',
    'GRAFANA_NONPROD_HOST', 'GRAFANA_PROD_HOST',
    'PROMETHEUS_NONPROD_HOST', 'PROMETHEUS_PROD_HOST',
    'ALERTMANAGER_NONPROD_HOST', 'ALERTMANAGER_PROD_HOST',
    'CONSUL_DEV_HOST', 'CONSUL_SIT_HOST', 'CONSUL_FAT_HOST', 'CONSUL_UAT_HOST', 'CONSUL_PROD_HOST',
    'RABBITMQ_DEV_HOST', 'RABBITMQ_SIT_HOST', 'RABBITMQ_FAT_HOST', 'RABBITMQ_UAT_HOST', 'RABBITMQ_PROD_HOST',
    'K3S_NONPROD_TRAEFIK_HOST', 'K3S_PROD_TRAEFIK_HOST',
]
missing = [k for k in required_keys if not env_vars.get(k) or 'CHANGE_ME' in env_vars.get(k, '')]
if missing:
    print(f"❌ .env 中以下变量未配置或仍是占位符：{', '.join(missing)}")
    exit(1)

ENV_VARS = env_vars  # 直接使用 .env 中的全部变量

def substitute_vars(content, env_vars):
    def replacer(match):
        return env_vars.get(match.group(1), match.group(0))
    return re.sub(r'\$\{(\w+)\}', replacer, content)

# 读取本地配置文件 → 替换变量 → 上传到远程
```

上传文件列表：
- `conf/nginx/nginx.conf`
- `conf/nginx/proxy_params`
- `conf/nginx/conf.d/*.conf`（所有配置文件）
- `docker-compose.yml`

### 步骤 4：创建日志目录

```bash
SSH_CMD "mkdir -p /opt/tech-stack/infra-nginx/logs"
```

### 步骤 5：远程执行 docker compose up

```bash
SSH_CMD "cd /opt/tech-stack/infra-nginx && docker compose up -d"
```

### 步骤 6：健康检查（最多 30 秒）

```bash
SSH_CMD "for i in \$(seq 1 6); do curl -sf http://localhost/health > /dev/null 2>&1 && echo READY && break; echo \"等待...\$i/6\"; sleep 5; done"
```

若健康检查失败，查看容器日志排查：

```bash
SSH_CMD "docker logs --tail 50 tech-infra-nginx 2>&1"
```

排障要点详见 `references/pitfalls.md`。

### 步骤 7：展示连接信息

```
infra-nginx 已在 ${HOST} 启动

健康检查：  http://${HOST}/health
HTTP 代理：  ${HOST}:80 → 内部 Web UI
GitLab SSH： ${HOST}:2222 → ${GITLAB_HOST}:2222
Nexus Docker： ${HOST}:8082 → ${NEXUS_HOST}:8082

可通过以下域名访问（需 DNS 已配置）：
  http://gitlab.renew.com
  http://nexus.renew.com
  http://harbor.renew.com
  http://apollo.renew.com
  http://grafana-nonprod-ui.renew.com
  http://consul-fat-ui.renew.com
  ...
```

> **预配置但尚未就绪的 upstream 行为**：infra-nginx 部署时已预配置全部反代规则；上游服务（GitLab、Nexus、Harbor、Apollo、LGT 栈、各环境 Consul/RabbitMQ、K3s Traefik 等）尚未部署完毕时，对应域名访问会返回 502/504，nginx 自身不受影响。各上游服务部署完成后域名即自动可用。

### 已预配置 upstream 清单

| upstream | 来源 .env 变量 | 反代域名 |
|---|---|---|
| GitLab Web/SSH | `GITLAB_HOST` | `gitlab.renew.com`、TCP :2222 |
| Nexus Web/Docker | `NEXUS_HOST` | `nexus.renew.com`、TCP :8082 |
| Harbor | `HARBOR_HOST` | `harbor.renew.com` |
| dnsmasq Web UI | `DNS_HOST` | `dns.renew.com` |
| Apollo Portal + 4 非生产 Config | `APOLLO_HOST` | `apollo.renew.com`、`apollo-config-{dev,sit,fat,uat}.renew.com` |
| Apollo Prod Config | `APOLLO_PROD_HOST` | `apollo-config-prod.renew.com` |
| Grafana × 2 | `GRAFANA_{NONPROD,PROD}_HOST` | `grafana-{nonprod,prod}-ui.renew.com` |
| Prometheus × 2 | `PROMETHEUS_{NONPROD,PROD}_HOST` | `prometheus-{nonprod,prod}-ui.renew.com` |
| Alertmanager × 2 | `ALERTMANAGER_{NONPROD,PROD}_HOST` | `alertmanager-{nonprod,prod}-ui.renew.com` |
| Consul × 5 | `CONSUL_{DEV,SIT,FAT,UAT,PROD}_HOST` | `consul-{env}-ui.renew.com` |
| RabbitMQ × 5 | `RABBITMQ_{DEV,SIT,FAT,UAT,PROD}_HOST` | `rabbitmq-{env}-ui.renew.com` |
| K3s Traefik × 2 | `K3S_{NONPROD,PROD}_TRAEFIK_HOST` | `*.{dev,sit,fat,uat}.web/api.renew.com`、`*.prod.web/api.renew.com` |

---

## 部署报告输出

> 部署完成后，必须在项目 `env/` 目录下生成或更新该服务的部署报告文件 `env/<service>.md`。

报告模板：

```markdown
# infra-nginx — 部署报告

| 项目 | 值 |
|------|-----|
| 部署日期 | YYYY-MM-DD |
| 目标机器 | <IP> |
| 部署目录 | /opt/tech-stack/infra-nginx/ |
| 容器名称 | tech-infra-nginx |
| 镜像 | nginx:1.27-alpine |
| 网络模式 | host |

## 端口

| 端口 | 用途 |
|------|------|
| 80 | HTTP 反向代理（内部 Web UI） |
| 2222 | TCP 透传（GitLab SSH） |
| 8082 | TCP 透传（Nexus Docker Registry） |

## 代理服务

| 域名 | 目标 |
|------|------|
| gitlab.renew.com | ${GITLAB_HOST}:8929 |
| nexus.renew.com | ${NEXUS_HOST}:8081 |
| harbor.renew.com | ${HARBOR_HOST}:8880 |
| apollo.renew.com | ${APOLLO_HOST}:8070 |
| grafana-nonprod-ui.renew.com | ${GRAFANA_NONPROD_HOST}:3000 |
| ... | ... |

## 验证结果

- [ ] 容器运行正常（healthy）
- [ ] 健康检查端点 `/health` 正常
- [ ] nginx 配置语法正确
- [ ] 端口 :80、:2222、:8082 监听正常
- [ ] HTTP 反代本地服务正常
- [ ] HTTP 反代跨机服务正常

## 备注

- 使用 host 网络模式
- 前置条件：Harbor 已迁移到 :8880
- DNS 更新后域名访问生效
```

报告文件路径：`<project_root>/env/infra-nginx.md`
