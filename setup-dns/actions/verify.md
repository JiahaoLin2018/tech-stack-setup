# Action: verify

验证 dnsmasq DNS 解析是否正常（支持本地和远程两种部署模式）。

## 命令格式

```
/setup-dns verify [--host <ip>] [--user <user>] [--password <pass>|--key <path>]
```

## 步骤

1. **快速失败：容器未运行则直接退出**：
   ```bash
   STATUS=$(ssh ... "docker inspect tech-dns --format='{{.State.Status}}' 2>/dev/null")
   if [ "$STATUS" != "running" ]; then
     echo "❌ dnsmasq 容器未运行（status=${STATUS:-不存在}）"
     echo "   请先执行 /setup-dns start --host $HOST ..."
     exit 1
   fi
   echo "✅ dnsmasq 容器运行中"
   ```

2. **从远程 .env 取出 INFRA_NGINX_IP**（后续判断"是否落入泛解析"必需）：
   ```bash
   INFRA_NGINX_IP=$(ssh ... "grep '^INFRA_NGINX_IP=' /opt/tech-stack/dns/.env | cut -d= -f2- | tr -d '\"' | sed 's/[[:space:]]*#.*//' | xargs")
   if [ -z "$INFRA_NGINX_IP" ] || echo "$INFRA_NGINX_IP" | grep -q CHANGE_ME; then
     echo "❌ 远程 .env 中 INFRA_NGINX_IP 未配置，无法判断泛解析行为，请先修正"
     exit 1
   fi
   ```

3. **验证 hosts.lan 直连域名**（**跳过 CHANGE_ME 占位行**）：
   ```bash
   ssh ... "grep -vE '^[[:space:]]*(#|$)' /opt/tech-stack/dns/hosts.lan | while read IP DOMAIN REST; do \
     case \"\$IP\" in CHANGE_ME*) echo \"⏭️  \$DOMAIN 跳过（IP 仍为占位符 \$IP）\"; continue ;; esac; \
     if command -v dig > /dev/null 2>&1; then \
       RESULT=\$(dig +short \"\$DOMAIN\" @127.0.0.1 2>/dev/null | head -1); \
     else \
       RESULT=\$(nslookup \"\$DOMAIN\" 127.0.0.1 2>/dev/null | awk '/^Address: / {print \$2}' | tail -1); \
     fi; \
     if [ \"\$RESULT\" = \"\$IP\" ]; then echo \"✅ \$DOMAIN → \$IP\"; else echo \"❌ \$DOMAIN 期望 \$IP，实际 \${RESULT:-无响应}\"; fi; \
   done"
   ```

4. **验证泛解析是否生效**：
   ```bash
   # 测试未在 hosts.lan 中定义的域名（应通过泛解析返回 INFRA_NGINX_IP）
   RESULT=$(ssh ... "dig grafana-nonprod-ui.renew.com @127.0.0.1 +short 2>/dev/null | head -1")
   if [ "$RESULT" = "$INFRA_NGINX_IP" ]; then
     echo "✅ 泛解析生效 → grafana-nonprod-ui.renew.com → $RESULT"
   else
     echo "❌ 泛解析异常 → 期望 $INFRA_NGINX_IP，实际 ${RESULT:-无响应}"
   fi
   ```

5. **验证上游 DNS 转发**：
   ```bash
   # 测试公网域名（应通过上游 DNS 解析）
   RESULT=$(ssh ... "dig baidu.com @127.0.0.1 +short 2>/dev/null | head -1")
   if [ -n "$RESULT" ] && [ "$RESULT" != "$INFRA_NGINX_IP" ]; then
     echo "✅ 上游 DNS 转发正常 → baidu.com → $RESULT"
   else
     echo "❌ 上游 DNS 转发异常 → 实际 ${RESULT:-无响应}"
   fi
   ```

6. **从本地测试远程 DNS 可达性**（**用泛解析覆盖的固定域名，不依赖 hosts.lan 实际值**）：
   ```bash
   nslookup grafana-nonprod-ui.renew.com $HOST 2>/dev/null \
     && echo "✅ 从本地可访问远程 DNS" \
     || echo "❌ 从本地无法访问远程 DNS，请检查防火墙端口 53"
   ```

7. **必备域名清单自检**（按分组逐项验证，避免硬编码总数）：
   ```bash
   ssh ... 'bash -s' <<'REMOTE_SH'
   MISSING=0
   for prefix in mysql redis mongodb rabbitmq consul; do
     for env in dev sit fat uat prod; do
       grep -q "${prefix}-${env}\.renew\.com" /opt/tech-stack/dns/hosts.lan \
         || { echo "❌ 缺失：${prefix}-${env}.renew.com"; MISSING=$((MISSING+1)); }
     done
   done
   for prefix in otel loki tempo prometheus alertmanager k3s; do
     for domain in nonprod prod; do
       grep -q "${prefix}-${domain}\.renew\.com" /opt/tech-stack/dns/hosts.lan \
         || { echo "❌ 缺失：${prefix}-${domain}.renew.com"; MISSING=$((MISSING+1)); }
     done
   done
   [ "$MISSING" -eq 0 ] && echo '✅ hosts.lan 必备域名清单完整' || echo "❌ hosts.lan 缺失 $MISSING 条必备域名"
   REMOTE_SH
   ```

8. **抽样直连域名解析**（验证 hosts.lan 精确匹配未被泛解析吞掉）：
   ```bash
   for D in mysql-dev.renew.com otel-nonprod.renew.com k3s-prod.renew.com; do
     # 先取该域名在 hosts.lan 中预期的 IP（可能是 CHANGE_ME_*，也可能是真实 IP）
     EXPECTED=$(ssh ... "grep -E '[[:space:]]${D}([[:space:]]|$)' /opt/tech-stack/dns/hosts.lan | awk '{print \$1}' | head -1")
     case "$EXPECTED" in
       CHANGE_ME*) echo "⏭️  $D 跳过（hosts.lan 中 IP 仍为 $EXPECTED）"; continue ;;
       '')         echo "❌ $D 未在 hosts.lan 中找到对应记录"; continue ;;
     esac
     RESULT=$(ssh ... "dig +short $D @127.0.0.1 | head -1")
     if [ "$RESULT" = "$EXPECTED" ]; then
       echo "✅ $D → $RESULT（直连命中）"
     elif [ "$RESULT" = "$INFRA_NGINX_IP" ]; then
       echo "❌ $D → $RESULT（落入泛解析；hosts.lan 未生效，请检查容器是否重启过）"
     else
       echo "❌ $D → 期望 $EXPECTED，实际 ${RESULT:-无响应}"
     fi
   done
   ```

## 验证清单

| 测试项 | 预期结果 | 说明 |
|--------|----------|------|
| 容器运行 | status=running | 未运行直接退出，提示先 start |
| hosts.lan 精确匹配 | 返回配置的 IP | 直连域名；CHANGE_ME 行自动跳过 |
| 泛解析域名 (grafana-nonprod-ui.renew.com) | 返回 INFRA_NGINX_IP | 代理域名通过 infra-nginx 反代 |
| 公网域名 (baidu.com) | 返回公网 IP（≠ INFRA_NGINX_IP） | 上游 DNS 转发正常 |
| 必备域名清单 | mysql/redis/mongodb/rabbitmq/consul × 5 环境 + otel/loki/tempo/prometheus/alertmanager/k3s × 2 域 全部存在 | 按分组校验，无硬编码总数 |
| 直连命中（抽样） | 返回 hosts.lan 中预期 IP（非 INFRA_NGINX_IP） | CHANGE_ME 占位时自动跳过 |
