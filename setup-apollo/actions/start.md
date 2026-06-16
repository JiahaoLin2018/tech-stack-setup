# action: start — 启动 Apollo

## `--env` 参数处理（D 类，执行前必须校验）

```bash
# ENV 由 Skill 框架从 --env 参数解析，默认 nonprod
case "${ENV:-nonprod}" in
  nonprod|prod) ;;
  *) echo "ERROR: --env 参数无效 '${ENV}'，合法值：nonprod|prod" && exit 1 ;;
esac
DEPLOY_DIR="/opt/tech-stack/apollo-${ENV:-nonprod}"
COMPOSE_FILE="docker-compose.${ENV:-nonprod}.yml"
```

## 步骤

> **文件上传约束**：上传 docker-compose.*.yml 等含 `${VAR}` 变量引用的文件时，必须使用文件复制方式（`scp` 或 `sftp.put()`），禁止使用 Python 字符串写入（会导致 `${VAR}` 被吞掉变为空值）。详见项目根目录 `references/deployment-principles.md` 前置准备第 6 节。

### 步骤 1：检查本地 SSH 工具

```bash
# 密码模式
which sshpass > /dev/null 2>&1 || echo "MISSING_SSHPASS"
# 密钥模式
ls ${SSH_KEY_PATH} 2>/dev/null || echo "MISSING_KEY"
```

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
SSH_CMD "mkdir -p ${DEPLOY_DIR}"

# 密码模式
sshpass -p "${SSH_PASSWORD}" scp -r -P ${SSH_PORT:-22} \
  ${CLAUDE_SKILL_DIR}/references/. ${SSH_USER:-root}@${HOST}:${DEPLOY_DIR}/

# 密钥模式
scp -i ${SSH_KEY_PATH} -r -P ${SSH_PORT:-22} \
  ${CLAUDE_SKILL_DIR}/references/. ${SSH_USER:-root}@${HOST}:${DEPLOY_DIR}/
```

### 步骤 5：激活对应的 docker-compose 文件

```bash
# 将对应模式的 compose 文件复制为 docker-compose.yml（供后续 docker compose 命令使用）
SSH_CMD "cp ${DEPLOY_DIR}/${COMPOSE_FILE} ${DEPLOY_DIR}/docker-compose.yml"
```

### 步骤 6：检查并初始化远程 .env

```bash
SSH_CMD "ls ${DEPLOY_DIR}/.env 2>/dev/null || cp ${DEPLOY_DIR}/.env.example ${DEPLOY_DIR}/.env"
SSH_CMD "grep -q 'CHANGE_ME_' ${DEPLOY_DIR}/.env && \
  echo 'WARNING: .env 中存在 CHANGE_ME_ 占位值，生产环境请先修改'"
```

### 步骤 7：停止旧容器（升级场景）

```bash
SSH_CMD "
OLD_CONTAINERS=\$(docker ps -a --format '{{.Names}}' | grep -E '^tech-apollo-' | head -1)
if [ -n \"\$OLD_CONTAINERS\" ]; then
  echo '检测到旧版容器，停止并移除...'
  cd ${DEPLOY_DIR} && docker compose down --remove-orphans
  echo '旧容器已清理'
fi
"
```

### 步骤 8：远程启动容器

```bash
SSH_CMD "cd ${DEPLOY_DIR} && docker compose up -d"
```

> ⚠️ `docker compose up -d` 因 healthcheck 链等待超时（SSH 连接断开）时，服务实际在后台继续启动。
> 稍后用 `docker compose up -d --no-recreate` 触发剩余服务即可。

### 步骤 9：等待 apollo-db 就绪（最多 90 秒）

```bash
SSH_CMD "for i in \$(seq 1 9); do
  docker inspect --format='{{.State.Health.Status}}' tech-apollo-db 2>/dev/null | grep -q 'healthy' && echo 'apollo-db: healthy' && break
  echo \"等待 apollo-db...\$i/9\"; sleep 10
done"
```

### 步骤 10：初始化 Apollo 数据库（仅首次部署）

> **nonprod 模式**：初始化 5 个 Schema（ApolloPortalDB + dev/sit/fat/uat）
> **prod 模式**：初始化 1 个 Schema（ApolloConfigDB_prod）

```bash
SSH_CMD "
cd ${DEPLOY_DIR}
source .env

# ---- 按模式确定需要初始化的环境列表 ----
if [ '${ENV:-nonprod}' = 'prod' ]; then
  ENV_LIST='prod'
  INIT_PORTAL='false'
else
  ENV_LIST='dev sit fat uat'
  INIT_PORTAL='true'
fi

# ---- 下载 SQL 模板 ----
if [ ! -f /tmp/apolloconfigdb.sql ]; then
  echo '下载 apolloconfigdb.sql...'
  curl -fsSL https://raw.githubusercontent.com/apolloconfig/apollo/v2.5.0/scripts/sql/profiles/mysql-default/apolloconfigdb.sql -o /tmp/apolloconfigdb.sql
fi

# ---- 初始化各环境 Config DB ----
for ENV_LOWER in \$ENV_LIST; do
  DB_NAME=\"ApolloConfigDB_\${ENV_LOWER}\"
  HAS_DB=\$(docker exec tech-apollo-db mysql -u root -p\"\${APOLLO_DB_ROOT_PASSWORD}\" -e 'SHOW DATABASES' 2>/dev/null | grep \"^\${DB_NAME}$\")
  if [ -z \"\$HAS_DB\" ]; then
    echo \"初始化 \${DB_NAME} (\${ENV_LOWER})...\"
    # 【重要】sed 必须覆盖 apolloconfigdb.sql 中所有写法（三种形式）
    sed \
      -e \"s/\\\`ApolloConfigDB\\\`/\\\`\${DB_NAME}\\\`/g\" \
      -e \"s/CREATE DATABASE IF NOT EXISTS ApolloConfigDB /CREATE DATABASE IF NOT EXISTS \\\`\${DB_NAME}\\\` /g\" \
      -e \"s/Use ApolloConfigDB;/USE \\\`\${DB_NAME}\\\`;/g\" \
      -e \"s/USE ApolloConfigDB;/USE \\\`\${DB_NAME}\\\`;/g\" \
      /tmp/apolloconfigdb.sql > /tmp/apolloconfigdb_\${ENV_LOWER}.sql
    # 【重要】必须先 docker cp 到容器内再执行，不能用 docker exec -i < file
    docker cp /tmp/apolloconfigdb_\${ENV_LOWER}.sql tech-apollo-db:/tmp/apolloconfigdb_\${ENV_LOWER}.sql
    docker exec tech-apollo-db bash -c \"mysql -u root -p'\${APOLLO_DB_ROOT_PASSWORD}' < /tmp/apolloconfigdb_\${ENV_LOWER}.sql\"
    # 验证表数量
    TBL_COUNT=\$(docker exec tech-apollo-db mysql -u root -p\"\${APOLLO_DB_ROOT_PASSWORD}\" -se \"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='\${DB_NAME}'\" 2>/dev/null)
    if [ \"\${TBL_COUNT:-0}\" -gt 0 ]; then
      # 修复 eureka URL 指向对应环境的 Config Service
      docker exec tech-apollo-db mysql -u root -p\"\${APOLLO_DB_ROOT_PASSWORD}\" \${DB_NAME} -e \"UPDATE ServerConfig SET Value='http://apollo-config-\${ENV_LOWER}:8080/eureka/' WHERE \\\`Key\\\`='eureka.service.url';\" 2>/dev/null
      echo \"\${DB_NAME} 初始化完成，共 \${TBL_COUNT} 张表\"
    else
      echo \"ERROR: \${DB_NAME} 初始化失败，表数量为 0\"
    fi
  else
    echo \"\${DB_NAME} 已存在，跳过初始化\"
  fi
done

# ---- 初始化 Portal 库（仅 nonprod 模式）----
if [ \"\$INIT_PORTAL\" = 'true' ]; then
  if [ ! -f /tmp/apolloportaldb.sql ]; then
    echo '下载 apolloportaldb.sql...'
    curl -fsSL https://raw.githubusercontent.com/apolloconfig/apollo/v2.5.0/scripts/sql/profiles/mysql-default/apolloportaldb.sql -o /tmp/apolloportaldb.sql
  fi
  HAS_PORTAL=\$(docker exec tech-apollo-db mysql -u root -p\"\${APOLLO_DB_ROOT_PASSWORD}\" -e 'SHOW DATABASES' 2>/dev/null | grep 'ApolloPortalDB')
  if [ -z \"\$HAS_PORTAL\" ]; then
    echo '初始化 ApolloPortalDB...'
    docker cp /tmp/apolloportaldb.sql tech-apollo-db:/tmp/apolloportaldb.sql
    docker exec tech-apollo-db bash -c \"mysql -u root -p'\${APOLLO_DB_ROOT_PASSWORD}' < /tmp/apolloportaldb.sql\"
    echo 'ApolloPortalDB 初始化完成'
  else
    echo 'ApolloPortalDB 已存在，跳过初始化'
  fi
fi

echo '数据库初始化完成'
"
```

### 步骤 11：优化 Apollo 默认配置（仅 nonprod 模式，首次部署后执行）

```bash
SSH_CMD "
if [ '${ENV:-nonprod}' != 'nonprod' ]; then echo '生产模式跳过 Portal 配置'; exit 0; fi
cd ${DEPLOY_DIR}
source .env

# PortalDB 配置优化
docker exec tech-apollo-db mysql -u root -p\"\${APOLLO_DB_ROOT_PASSWORD}\" --default-character-set=utf8mb4 -e \"
UPDATE ApolloPortalDB.ServerConfig SET Value='\${APOLLO_PORTAL_ENVS}' WHERE \\\`Key\\\`='apollo.portal.envs';
UPDATE ApolloPortalDB.ServerConfig SET Value='\${APOLLO_ORGANIZATIONS}' WHERE \\\`Key\\\`='organizations';
UPDATE ApolloPortalDB.ServerConfig SET Value='\${APOLLO_CONSUMER_TOKEN_SALT}' WHERE \\\`Key\\\`='consumer.token.salt';
UPDATE ApolloPortalDB.ServerConfig SET Value='\${APOLLO_CONFIG_VIEW_MEMBER_ONLY_ENVS}' WHERE \\\`Key\\\`='configView.memberOnly.envs';
\" 2>/dev/null
echo 'PortalDB 配置优化完成'

# ConfigDB 配置优化（非生产各环境）
for ENV_LOWER in dev sit fat uat; do
  docker exec tech-apollo-db mysql -u root -p\"\${APOLLO_DB_ROOT_PASSWORD}\" -e \"
  UPDATE ApolloConfigDB_\${ENV_LOWER}.ServerConfig SET Value='\${APOLLO_NAMESPACE_LOCK_SWITCH}' WHERE \\\`Key\\\`='namespace.lock.switch';
  \" 2>/dev/null
done
echo 'ConfigDB 配置优化完成'
"
```

### 步骤 12：重启 Portal 使配置生效（仅 nonprod 模式）

```bash
SSH_CMD "
if [ '${ENV:-nonprod}' != 'nonprod' ]; then exit 0; fi
docker restart tech-apollo-portal && echo 'Portal 已重启，等待服务就绪...'
"
```

### 步骤 13：等待服务就绪

```bash
# nonprod 模式：等待 apollo-config-dev 就绪（最多 120 秒）
# prod 模式：等待 apollo-config-prod 就绪（最多 120 秒）
SSH_CMD "
if [ '${ENV:-nonprod}' = 'prod' ]; then
  CHECK_PORT=\${APOLLO_CONFIG_PORT_PROD:-8605}
  CHECK_NAME='apollo-config-prod'
else
  CHECK_PORT=\${APOLLO_CONFIG_PORT_DEV:-8601}
  CHECK_NAME='apollo-config-dev'
fi
for i in \$(seq 1 8); do
  curl -s http://localhost:\${CHECK_PORT}/health | grep -q '\"status\":\"UP\"' && echo \"\${CHECK_NAME}: UP\" && break
  echo \"等待 \${CHECK_NAME}...\$i/8\"; sleep 15
done"
```

### 步骤 14：展示连接信息

**nonprod 模式**：
```
✅ Apollo [nonprod] 已在 ${HOST} 启动（10 个容器）

Portal UI：  http://apollo.renew.com（apollo/admin，首次登录后请修改密码）

各环境 Config Service（Spring Boot 接入域名）：
  DEV → http://apollo-config-dev.renew.com
  SIT → http://apollo-config-sit.renew.com
  FAT → http://apollo-config-fat.renew.com
  UAT → http://apollo-config-uat.renew.com
  PRO → 待阶段四 setup-apollo --env prod 后接入

Spring Boot 示例（按环境选择域名）：
  apollo.meta=http://apollo-config-dev.renew.com
```

**prod 模式**：
```
✅ Apollo [prod] 已在 ${HOST} 启动（3 个容器）

生产 Config Service：http://apollo-config-prod.renew.com
生产 Admin Service（仅 Portal 内部）：http://${HOST}:8615

接下来：在非生产 Apollo Portal 中将 PRO 环境 Meta Server 更新为：
  http://apollo-config-prod.renew.com

Spring Boot 生产接入：
  apollo.meta=http://apollo-config-prod.renew.com
```

---

## 部署报告输出

> 部署完成后，必须在项目 `env/` 目录下生成部署报告 `env/apollo-{nonprod|prod}.md`。

报告模板：

```markdown
# Apollo [{ENV}] — 部署报告

| 项目 | 值 |
|------|-----|
| 部署日期 | YYYY-MM-DD |
| 目标机器 | <IP> |
| 部署目录 | /opt/tech-stack/apollo-{nonprod|prod}/ |
| 容器数量 | 10（nonprod）/ 3（prod） |
| 镜像 | mysql:8.4 / apolloconfig/*:2.5.0 |

## 端口总览

| 环境 | Config Service | Admin Service |
|------|----------------|---------------|
| DEV  | 8601 | 8611 |
| SIT  | 8602 | 8612 |
| FAT  | 8603 | 8613 |
| UAT  | 8604 | 8614 |
| PRO  | 8605 | 8615 |
| Portal | 8070 | — |
| MySQL | 3307 | — |

## 数据库分配

| 环境 | Schema |
|------|--------|
| DEV  | ApolloConfigDB_dev |
| SIT  | ApolloConfigDB_sit |
| FAT  | ApolloConfigDB_fat |
| UAT  | ApolloConfigDB_uat |
| PRO  | ApolloConfigDB_prod（生产独立实例） |
| Portal | ApolloPortalDB（nonprod） |

## 账号密码

| 用途 | 用户 | 密码 |
|------|------|------|
| Apollo Portal | apollo | admin（首次登录后修改） |
| Apollo MySQL | root | <APOLLO_DB_ROOT_PASSWORD> |

## Spring Boot 接入

| 环境 | apollo.meta |
|------|-------------|
| dev | http://apollo-config-dev.renew.com |
| sit | http://apollo-config-sit.renew.com |
| fat | http://apollo-config-fat.renew.com |
| uat | http://apollo-config-uat.renew.com |
| prod | http://apollo-config-prod.renew.com |
```
