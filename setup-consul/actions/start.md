# action: start — 启动 Consul

## `--env` 参数处理（A 类，执行前必须校验）

```bash
# ENV 由 Skill 框架从 --env 参数解析，默认 dev
case "${ENV:-dev}" in
  dev|sit|fat|uat|prod) ;;
  *) echo "ERROR: --env 参数无效 '${ENV}'，合法值：dev|sit|fat|uat|prod" && exit 1 ;;
esac
DEPLOY_DIR="/opt/tech-stack/consul-${ENV:-dev}"
CONTAINER_NAME="tech-consul-${ENV:-dev}"
```

## 步骤

> **文件上传约束**：上传 docker-compose.yml 等含 `${VAR}` 变量引用的文件时，必须使用文件复制方式（`scp` 或 `sftp.put()`），禁止使用 Python 字符串写入（会导致 `${VAR}` 被吞掉变为空值）。详见项目根目录 `references/deployment-principles.md` 前置准备第 6 节。

### 步骤 1：检查本地 SSH 工具

```bash
# 密码模式
which sshpass > /dev/null 2>&1 || echo "MISSING_SSHPASS"
# 密钥模式
ls ${SSH_KEY_PATH} 2>/dev/null || echo "MISSING_KEY"
```

- 缺少 sshpass（密码模式）→ 提示 `apt install sshpass` 或改用 `--key`
- 密钥文件不存在 → 提示检查路径

### 步骤 2：测试 SSH 连接

```bash
# 密码模式
sshpass -p "${SSH_PASSWORD}" ssh -o StrictHostKeyChecking=no -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} "echo OK"
# 密钥模式
ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} "echo OK"
```

- 连接失败 → 报告错误信息，终止执行

### 步骤 3：检查远程 Docker（未安装则自动安装）

```bash
SSH_CMD "docker info > /dev/null 2>&1 || (curl -fsSL https://get.docker.com | sh && systemctl enable --now docker)"
```

### 步骤 4：创建远程部署目录并上传 references/

```bash
SSH_CMD "mkdir -p ${DEPLOY_DIR}/conf ${DEPLOY_DIR}/data"

# 密码模式
sshpass -p "${SSH_PASSWORD}" scp -r -P ${SSH_PORT:-22} \
  ${CLAUDE_SKILL_DIR}/references/. ${SSH_USER:-root}@${HOST}:${DEPLOY_DIR}/

# 密钥模式
scp -i ${SSH_KEY_PATH} -r -P ${SSH_PORT:-22} \
  ${CLAUDE_SKILL_DIR}/references/. ${SSH_USER:-root}@${HOST}:${DEPLOY_DIR}/
```

### 步骤 5：检查并初始化远程 .env

```bash
SSH_CMD "ls ${DEPLOY_DIR}/.env 2>/dev/null || cp ${DEPLOY_DIR}/.env.example ${DEPLOY_DIR}/.env"
# 注入 CONSUL_ENV（确保 docker-compose.yml 中的容器名使用正确的环境值）
SSH_CMD "grep -q '^CONSUL_ENV=' ${DEPLOY_DIR}/.env && \
  sed -i \"s/^CONSUL_ENV=.*/CONSUL_ENV=${ENV:-dev}/\" ${DEPLOY_DIR}/.env || \
  echo \"CONSUL_ENV=${ENV:-dev}\" >> ${DEPLOY_DIR}/.env"
# 检查是否含未替换的占位值
SSH_CMD "grep -q 'CHANGE_ME_' ${DEPLOY_DIR}/.env && \
  echo 'WARNING: .env 中存在 CHANGE_ME_ 占位值，生产环境请先修改'"
```

### 步骤 6：渲染配置文件（envsubst）

> 使用 `envsubst` 将 `.env` 变量渲染到 `consul.hcl`，统一配置管理。

```bash
SSH_CMD "
# 检查 envsubst 是否可用
if ! command -v envsubst &>/dev/null; then
  echo 'envsubst 未安装，请先安装: sudo apt-get install -y gettext-base (或 yum install -y gettext)'
  exit 1
fi
cd ${DEPLOY_DIR}
set -a && source .env && set +a
envsubst '\${CONSUL_LOG_LEVEL}' < conf/consul.hcl.tpl > conf/consul.hcl
echo 'consul.hcl 配置渲染完成'
"
```

**渲染的变量**：
- `CONSUL_LOG_LEVEL`：日志等级（默认 WARN）

> Gossip 加密 / ACL 不在 .env 中维护。如需启用，编辑 `conf/consul.hcl.tpl` 取消对应注释段（含完整启用步骤和密钥生成命令）。

### 步骤 7：远程执行 docker compose up

```bash
SSH_CMD "cd ${DEPLOY_DIR} && docker compose up -d"
```

### 步骤 8：远程健康检查（最多 30 秒）

```bash
SSH_CMD "for i in \$(seq 1 6); do \
  docker exec ${CONTAINER_NAME} consul operator raft list-peers > /dev/null 2>&1 && echo 'READY' && break; \
  echo \"等待...\$i/6\"; sleep 5; \
done"
```

### 步骤 9：展示连接信息

```
✅ Consul [${ENV:-dev}] 已在 ${HOST} 启动

直连地址（Pod 直连，需已写入 hosts.lan）：
  consul-${ENV:-dev}.renew.com:8500

Web UI（通过 infra-nginx 代理，无需端口）：
  http://consul-${ENV:-dev}-ui.renew.com

Spring Boot 接入：
  spring.cloud.consul.host=consul-${ENV:-dev}.renew.com
  spring.cloud.consul.port=8500
```

---

## 部署报告输出

> 部署完成后，必须在项目 `env/` 目录下生成或更新部署报告文件 `env/consul-{env}.md`。

报告模板：

```markdown
# Consul [{ENV}] — 部署报告

| 项目 | 值 |
|------|-----|
| 部署日期 | YYYY-MM-DD |
| 目标机器 | <IP> |
| 部署目录 | /opt/tech-stack/consul-{env}/ |
| 容器名称 | tech-consul-{env} |
| 镜像 | hashicorp/consul:1.20 |
| 环境 | {env} |

## 端口

| 端口 | 用途 |
|------|------|
| 8500 | HTTP API / Web UI（通过 infra-nginx 代理到 consul-{env}-ui.renew.com） |
| 8600/udp | DNS 端口 |

## 连接方式

| 方式 | 地址 |
|------|------|
| 直连（Pod/服务） | consul-{env}.renew.com:8500（需已写入 hosts.lan） |
| Web UI | http://consul-{env}-ui.renew.com（infra-nginx 代理） |

## Spring Boot 接入

```yaml
spring.cloud.consul.host: consul-{env}.renew.com
spring.cloud.consul.port: 8500
```

## 备注

- <部署过程中的特殊配置或踩坑记录>
```