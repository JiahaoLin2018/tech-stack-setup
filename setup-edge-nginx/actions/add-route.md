# Action: add-route

添加新路由（支持公开/白名单模式）。

## 参数解析

### 必填参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `--env` | 环境（nonprod\|prod） | prod |
| `--domain` | 精确域名 | admin.prod.web.renew.com |
| `--mode` | 访问模式（public\|whitelist） | whitelist |

### 可选参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `--ips` | IP 白名单（仅 whitelist 模式） | "192.168.1.0/24,10.0.0.0/8" |

## 访问模式说明

| 模式 | 说明 | 配置文件 |
|------|------|---------|
| **public** | 公开访问，任意 IP 可访问 | 20-nonprod-routes.conf / 20-prod-routes.conf（通配已覆盖） |
| **whitelist** | IP 白名单，仅指定 IP 可访问 | 30-whitelist-routes.conf |

## 执行步骤

### Step 0：参数校验

```bash
# --env 默认 nonprod（B 类契约）
ENV="${ENV:-nonprod}"
if [[ "$ENV" != "nonprod" && "$ENV" != "prod" ]]; then
    echo "[ERROR] --env 必须为 nonprod 或 prod"
    exit 1
fi

# 验证 --mode
if [[ "$MODE" != "public" && "$MODE" != "whitelist" ]]; then
    echo "[ERROR] --mode 必须为 public 或 whitelist"
    exit 1
fi

# 验证 --domain 格式
if [[ ! "$DOMAIN" =~ ^[a-z0-9-]+\.(dev|sit|fat|uat|prod)\.(web|api)\.renew\.com$ ]]; then
    echo "[WARN] 域名格式不符合规范: $DOMAIN"
    echo "  建议: {project}.{env}.{type}.renew.com"
fi

# whitelist 模式必须提供 --ips
if [[ "$MODE" == "whitelist" && -z "$IPS" ]]; then
    echo "[ERROR] whitelist 模式必须提供 --ips 参数"
    exit 1
fi
```

### Step 1：确定部署目录

```bash
DEPLOY_DIR="/opt/tech-stack/edge-nginx-${ENV}"
```

### Step 2：生成 server block 配置

#### public 模式

公开域名通常已被通配路由覆盖，无需额外配置。

若需添加独立配置（如特殊代理参数），生成：

```nginx
# 公开路由 - ${DOMAIN}
server {
    listen 443 ssl;
    server_name ${DOMAIN};
    
    include /etc/nginx/includes/ssl-params.conf;
    include /etc/nginx/includes/security-headers.conf;
    
    location / {
        proxy_pass http://k3s_${ENV};
        include /etc/nginx/includes/proxy-params.conf;
    }
}
```

#### whitelist 模式

生成带 IP 白名单的配置：

```nginx
# IP 白名单路由 - ${DOMAIN}
# 白名单 IP: ${IPS}
server {
    listen 443 ssl;
    server_name ${DOMAIN};
    
    include /etc/nginx/includes/ssl-params.conf;
    include /etc/nginx/includes/security-headers.conf;
    
    # IP 白名单
    allow ${IP1};
    allow ${IP2};
    deny all;
    
    location / {
        proxy_pass http://k3s_${ENV};
        include /etc/nginx/includes/proxy-params.conf;
    }
}
```

### Step 3：追加配置到 30-whitelist-routes.conf

```bash
# 追加 server block 到白名单配置文件
<SSH> cat >> ${DEPLOY_DIR}/conf.d/30-whitelist-routes.conf << 'EOF'

# ${DOMAIN} - ${MODE} - ${TIMESTAMP}
server {
    listen 443 ssl;
    server_name ${DOMAIN};
    
    include /etc/nginx/includes/ssl-params.conf;
    include /etc/nginx/includes/security-headers.conf;
    
    # IP 白名单
    ${ALLOW_RULES}
    
    location / {
        proxy_pass http://k3s_${ENV};
        include /etc/nginx/includes/proxy-params.conf;
    }
}
EOF
```

### Step 4：验证配置语法

```bash
<SSH> docker exec tech-edge-nginx-${ENV} nginx -t
```

### Step 5：热加载配置

```bash
<SSH> docker exec tech-edge-nginx-${ENV} nginx -s reload
```

### Step 6：验证访问

```bash
# 测试 HTTPS 访问
<SSH> curl -k -s -o /dev/null -w "%{http_code}" https://localhost/ -H "Host: ${DOMAIN}"
```

## 示例

### 添加公开域名

```bash
/setup-edge-nginx add-route --env prod --domain api.v2.prod.web.renew.com --mode public
```

> 注意：公开域名通常已被通配路由覆盖，无需额外配置。

### 添加白名单域名

```bash
/setup-edge-nginx add-route --env prod \
  --domain admin.prod.web.renew.com \
  --mode whitelist \
  --ips "192.168.1.0/24,10.0.0.0/8"
```

### 添加多 IP 白名单

```bash
/setup-edge-nginx add-route --env nonprod \
  --domain internal.fat.api.renew.com \
  --mode whitelist \
  --ips "192.168.1.0/24,10.0.0.0/8,203.0.113.50"
```

## 输出

```
==========================================
路由添加成功
==========================================
环境: ${ENV}
域名: ${DOMAIN}
模式: ${MODE}
白名单: ${IPS:-无}

配置已追加到: conf.d/30-whitelist-routes.conf

验证访问:
  curl -k https://${HOST}/ -H "Host: ${DOMAIN}"
==========================================
```

## 注意事项

1. **域名唯一性** — 同一域名不能重复添加
2. **优先级** — 精确域名匹配优先于通配匹配
3. **IP 格式** — 支持 CIDR 格式（如 192.168.1.0/24）
4. **热加载** — 配置变更后自动 reload，无需重启容器
