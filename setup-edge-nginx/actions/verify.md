# Action: verify

验证 edge-nginx 配置正确性。

## 参数解析

### Step 0：--env 参数解析（B 类契约）

从用户指令中提取 --env 参数：
- 若未传入 → 默认 `nonprod`
- 若值为 `nonprod` 或 `prod` → 正常执行
- 若值非法 → 报错退出

### Step 1：检查容器运行状态

```bash
<SSH> docker ps --filter "name=tech-edge-nginx-${ENV}" --format "{{.Status}}"
```

预期输出包含 `Up`。

### Step 2：检查 SSL 证书

```bash
<SSH> ls -la /opt/tech-stack/edge-nginx-${ENV}/ssl/
```

预期输出包含 `fullchain.pem` 和 `privkey.pem`。

### Step 3：检查健康检查端点

```bash
<SSH> curl -sf http://localhost:8888/health
```

预期返回 `OK`。

### Step 4：检查 HTTPS 访问

```bash
# 测试 HTTPS 端点（根据环境确定域名后缀）
# nonprod → fat, prod → prod
<SSH> curl -k -s -o /dev/null -w "%{http_code}" https://localhost:443/ -H "Host: demo.${DOMAIN_SUFFIX}.web.renew.com"
```

预期返回 200 或 502（后端不可达时）。

### Step 5：检查 HTTP→HTTPS 重定向

```bash
<SSH> curl -s -o /dev/null -w "%{http_code}" http://localhost:80/ -H "Host: demo.${DOMAIN_SUFFIX}.web.renew.com"
```

预期返回 301。

### Step 6：检查安全头

```bash
<SSH> curl -k -I https://localhost:443/ -H "Host: demo.${DOMAIN_SUFFIX}.web.renew.com" 2>/dev/null | grep -E "X-Frame-Options|Strict-Transport-Security|X-Content-Type-Options"
```

预期输出包含安全头。

### Step 7：检查 nginx 配置语法

```bash
<SSH> docker exec tech-edge-nginx-${ENV} nginx -t
```

预期输出：
```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

### Step 8：检查后端连通性

```bash
# 从 .env 读取 K3S 地址
K3S_HOST=$(grep "^K3S_${ENV_UPPER}_HOST=" .env | cut -d'=' -f2)
K3S_PORT=$(grep "^K3S_${ENV_UPPER}_PORT=" .env | cut -d'=' -f2)

<SSH> curl -s -o /dev/null -w "%{http_code}" http://${K3S_HOST}:${K3S_PORT}/health --connect-timeout 5
```

预期返回 200（若 K3s 有健康检查端点）。

## 验证结果

```
==========================================
edge-nginx 验证结果
==========================================
环境: ${ENV}

[✓] 容器运行状态: Up
[✓] SSL 证书: 存在
[✓] 健康检查端点: OK
[✓] HTTPS 访问: 200
[✓] HTTP 重定向: 301
[✓] 安全头: 已配置
[✓] nginx 配置语法: 正确
[✓] 后端连通性: 200

验证通过！
==========================================
```

## 预期正常输出示例

```
Up 2 hours (healthy)

total 8
drwxr-xr-x 2 root root 4096 Apr 20 10:00 .
drwxr-xr-x 3 root root 4096 Apr 20 10:00 ..
-rw-r--r-- 1 root root 3585 Apr 20 10:00 fullchain.pem
-rw------- 1 root root 1704 Apr 20 10:00 privkey.pem

OK

200

301

X-Frame-Options: SAMEORIGIN
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff

nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful

200
```

## 完整验证（DNS 配置后）

```bash
# HTTPS 验证（需公网 DNS 已更新）
curl -k https://demo.${DOMAIN_SUFFIX}.web.renew.com/

# 检查证书有效期
echo | openssl s_client -connect ${HOST}:443 2>/dev/null | openssl x509 -noout -dates
```

## 常见问题

| 检查项 | 失败原因 | 解决方案 |
|--------|---------|---------|
| 容器状态 | 未运行 | 执行 start |
| SSL 证书 | 不存在 | 上传证书 |
| 健康检查 | 端口未监听 | 检查容器日志 |
| HTTPS 访问 | 证书配置错误 | 检查 ssl-params.conf |
| HTTP 重定向 | 配置错误 | 检查 10-https-redirect.conf |
| 安全头 | 未包含 | 检查 includes/security-headers.conf |
| 后端连通性 | K3s 不可达 | 检查 K3S_HOST/PORT 配置 |
