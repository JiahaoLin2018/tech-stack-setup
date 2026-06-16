# Action: start

在公网边界部署并启动 nginx 边缘网关。

## 参数解析

### Step 0：--env 参数解析（B 类契约）

从用户指令中提取 --env 参数：
- 若未传入 → 默认 `nonprod`
- 若值为 `nonprod` 或 `prod` → 正常执行
- 若值非法 → 报错退出：`[ERROR] --env 必须为 nonprod 或 prod，当前值：${ENV_VALUE}`

### Step 1：确定配置

按 --env 值选择：

| 配置项 | nonprod | prod |
|--------|---------|------|
| K3S_HOST | ${K3S_NONPROD_HOST} | ${K3S_PROD_HOST} |
| K3S_PORT | ${K3S_NONPROD_PORT} | ${K3S_PROD_PORT} |
| ROUTES_CONF | 20-nonprod-routes.conf | 20-prod-routes.conf |
| 容器名 | tech-edge-nginx-nonprod | tech-edge-nginx-prod |
| 部署目录 | /opt/tech-stack/edge-nginx-nonprod/ | /opt/tech-stack/edge-nginx-prod/ |

### Step 2：读取 .env 配置

从 `<skill_dir>/references/.env` 读取：
- K3S_NONPROD_HOST / K3S_NONPROD_PORT
- K3S_PROD_HOST / K3S_PROD_PORT
- WHITELIST_IPS（可选）

若 .env 不存在，提示用户先配置：
```
[ERROR] references/.env 不存在，请先配置:
  cp references/.env.example references/.env
  # 然后编辑 .env 文件
```

### Step 3：前置检查

#### 3.0 确认公网业务域名

在执行后续步骤前，向用户确认 `references/conf/nginx/conf.d/20-${ENV}-routes.conf` 中 `server_name` 正则使用的域名（默认 `*.${ENV}.web/api.renew.com`）是否为部署方实际持有的公网主域名。

提示文案：

```
[CONFIRM] edge-nginx 公网域名核对：
  当前 server_name 正则：*.${ENV}.web/api.renew.com（参考实现）
  请确认：
    1. 部署方实际公网主域名是否一致？如不一致，请先编辑：
       references/conf/nginx/conf.d/20-${ENV}-routes.conf
       将正则中的 renew\.com 替换为实际主域名（注意正则转义）
    2. SSL 证书 fullchain.pem 是否覆盖实际主域名？
    3. 公网 DNS A 记录是否已指向本机公网 IP？
  确认后继续部署。
```

如部署方明确仍使用参考域名（如内部演练 / 自有 renew.com），跳过提示继续。

#### 3.1 检查 SSL 证书

```bash
<SSH> ls -la ${DEPLOY_DIR}/ssl/fullchain.pem ${DEPLOY_DIR}/ssl/privkey.pem
```

若不存在，提示用户先上传证书：
```
[ERROR] SSL 证书不存在，请先上传:
  scp fullchain.pem privkey.pem ${USER}@${HOST}:${DEPLOY_DIR}/ssl/
```

#### 3.2 检查 K3s 后端可达性

```bash
<SSH> curl -s -o /dev/null -w "%{http_code}" http://${K3S_HOST}:${K3S_PORT}/health --connect-timeout 5
```

若返回非 200，警告但继续执行（K3s 可能尚未部署健康检查端点）。

### Step 4：创建部署目录

```bash
<SSH> mkdir -p ${DEPLOY_DIR}/{conf.d,includes,ssl,logs}
```

### Step 5：本地替换变量后上传配置文件

> **渲染规则**：所有 `${VAR}` 占位符在本地用 Python 正则替换为 `.env` 中的真实值，再通过 `paramiko` SFTP 上传到 DMZ 节点。正则只匹配 `${VAR}` 形式，nginx 内置变量（`$host` / `$remote_addr` 等）原样保留。
>
> envsubst 的具体踩坑见 `references/pitfalls.md` §11。

使用 Python 执行变量替换：

```python
import re

# 1. 确定运行环境与目标配置
env = "${ENV}"  # nonprod 或 prod
k3s_host_key = f"K3S_{env.upper()}_HOST"
k3s_port_key = f"K3S_{env.upper()}_PORT"
routes_conf = f"20-{env}-routes.conf"

# 2. 读取 .env 变量
env_vars = {}
with open('references/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, v = line.split('=', 1)
            env_vars[k.strip()] = v.strip()

# 3. 构造渲染字典
render_vars = {
    'ENV': env,
    'K3S_HOST': env_vars.get(k3s_host_key, ''),
    'K3S_PORT': env_vars.get(k3s_port_key, '8083')
}

# 校验必填项
missing = [k for k, v in render_vars.items() if not v or 'CHANGE_ME' in v]
if missing:
    print(f"❌ 以下变量未配置或为空：{', '.join(missing)}")
    exit(1)

def substitute_vars(content):
    def replacer(match):
        return render_vars.get(match.group(1), match.group(0))
    return re.sub(r'\$\{(\w+)\}', replacer, content)

# 4. 通过 paramiko 上传：含 ${VAR} 的文本文件先本地渲染再 sftp.put 写入临时文件，
#    无变量的二进制 / 模板（如 docker-compose.yml）直接 sftp.put 原文件
import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(hostname=HOST, username=USER, key_filename=KEY_PATH)  # 或 password=PASSWORD
sftp = ssh.open_sftp()

def upload_rendered(local_path, remote_path):
    with open(local_path) as f:
        rendered = substitute_vars(f.read())
    with sftp.open(remote_path, 'w') as r:
        r.write(rendered)

def upload_raw(local_path, remote_path):
    sftp.put(local_path, remote_path)
```

上传文件列表映射关系：

| 本地路径 | 远端路径 | 渲染策略 |
|---|---|---|
| `references/conf/nginx/nginx.conf` | `${DEPLOY_DIR}/nginx.conf` | `upload_rendered` |
| `references/conf/nginx/conf.d/${ROUTES_CONF}` | `${DEPLOY_DIR}/conf.d/${ROUTES_CONF}` | `upload_rendered`（注入 K3S_HOST / K3S_PORT） |
| `references/conf/nginx/conf.d/` 下其余 `.conf` | `${DEPLOY_DIR}/conf.d/` | `upload_rendered` |
| `references/conf/nginx/includes/*` | `${DEPLOY_DIR}/includes/` | `upload_rendered` |
| `references/docker-compose.yml` | `${DEPLOY_DIR}/docker-compose.yml` | `upload_raw`（含 `${ENV}`，由 `docker compose --env-file` 注入） |

### Step 6：验证配置语法

```bash
<SSH> cd ${DEPLOY_DIR} && docker run --rm -v $(pwd)/nginx.conf:/etc/nginx/nginx.conf:ro -v $(pwd)/conf.d:/etc/nginx/conf.d:ro -v $(pwd)/includes:/etc/nginx/includes:ro nginx:1.27-alpine nginx -t
```

若失败，检查配置文件语法。

### Step 7：启动容器

```bash
<SSH> cd ${DEPLOY_DIR} && ENV=${ENV} docker compose up -d
```

### Step 8：验证部署

```bash
# 等待容器启动
sleep 5

# 检查容器状态
<SSH> docker ps --filter "name=${CONTAINER_NAME}" --format "{{.Status}}"

# 检查端口监听
<SSH> ss -tlnp | grep -E ":80|:443"

# 测试健康检查端点
<SSH> curl -sf http://localhost:8888/health
```

### Step 9：输出部署信息

```
==========================================
部署完成！
==========================================
环境: ${ENV}
容器名: ${CONTAINER_NAME}
部署目录: ${DEPLOY_DIR}
后端地址: ${K3S_HOST}:${K3S_PORT}

访问测试:
  curl -k https://${HOST}/ -H "Host: demo.${ENV}.web.renew.com"

添加白名单路由:
  /setup-edge-nginx add-route --env ${ENV} --domain <domain> --mode whitelist --ips "<ip-list>"
==========================================
```

## 错误处理

| 错误 | 原因 | 解决方案 |
|------|------|---------|
| SSL 证书不存在 | 未上传证书 | 上传 fullchain.pem 和 privkey.pem |
| nginx -t 失败 | 配置语法错误 | 检查 conf.d/*.conf 文件 |
| 容器启动失败 | 端口被占用 | 检查 80/443 端口占用情况 |
| 后端不可达 | K3s 未就绪 | 确认 K3s 已部署且 K3S_HOST 正确 |

---

## 部署报告输出

> 部署完成后，必须在项目 `env/` 目录下生成或更新该服务的部署报告文件 `env/edge-nginx-${ENV}.md`。

报告模板：

```markdown
# edge-nginx-${ENV} — 部署报告

| 项目 | 值 |
|------|-----|
| 部署日期 | YYYY-MM-DD |
| 环境 | ${ENV} |
| 目标机器 | <IP> |
| 部署目录 | /opt/tech-stack/edge-nginx-${ENV}/ |
| 容器名称 | tech-edge-nginx-${ENV} |
| 镜像 | nginx:1.27-alpine |
| 网络模式 | host |

## 端口

| 端口 | 用途 |
|------|------|
| 80 | HTTP（重定向到 HTTPS） |
| 443 | HTTPS（业务流量入口） |
| 8888 | 健康检查端点 |

## 后端配置

| 配置项 | 值 |
|--------|-----|
| K3S_HOST | ${K3S_HOST} |
| K3S_PORT | ${K3S_PORT} |
| 路由配置 | conf.d/20-${ENV}-routes.conf |

## SSL 证书

| 文件 | 路径 |
|------|------|
| 证书 | ${DEPLOY_DIR}/ssl/fullchain.pem |
| 私钥 | ${DEPLOY_DIR}/ssl/privkey.pem |

## 处理域名

| 域名模式 | 说明 |
|---------|------|
| *.{env}.web.renew.com | 前端应用 |
| *.{env}.api.renew.com | API 网关 |

## 验证结果

- [ ] 容器运行正常（healthy）
- [ ] 健康检查端点 :8888/health 正常
- [ ] nginx 配置语法正确
- [ ] 端口 :80、:443 监听正常
- [ ] HTTP→HTTPS 重定向正常
- [ ] 安全头已配置
- [ ] 后端 K3s 连通性正常

## 备注

- 部署在 DMZ 公网边界
- 使用 host 网络模式
- 白名单路由通过 add-route action 添加
```

报告文件路径：`<project_root>/env/edge-nginx-${ENV}.md`
