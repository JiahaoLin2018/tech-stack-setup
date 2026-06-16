# setup-edge-nginx 运维陷阱

## 1. SSL 证书未上传导致启动失败

**现象**：容器启动后 nginx 报错 `cannot load certificate`。

**根因**：SSL 证书文件未上传到 `ssl/` 目录。

**解决方案**：
```bash
# 上传证书
scp fullchain.pem privkey.pem root@<dmz-ip>:/opt/tech-stack/edge-nginx-prod/ssl/

# 重启容器
docker restart tech-edge-nginx-prod
```

---

## 2. HTTP 请求被重定向到 HTTPS

**现象**：HTTP 请求返回 301，无法访问。

**根因**：edge-nginx 统一使用 HTTPS，HTTP 请求自动重定向。

**解决方案**：使用 HTTPS 访问：
```bash
curl -k https://demo.prod.web.renew.com/
```

---

## 3. 白名单域名无法访问（返回 403）

**现象**：访问白名单域名返回 403 Forbidden。

**根因**：客户端 IP 不在白名单中。

**解决方案**：
1. 检查客户端 IP
2. 使用 add-route 添加 IP：
```bash
/setup-edge-nginx add-route --env prod --domain admin.prod.web.renew.com --mode whitelist --ips "新IP段"
```

---

## 4. 后端 K3s 不可达

**现象**：HTTPS 访问返回 502 Bad Gateway。

**根因**：K3S_HOST 或 K3S_PORT 配置错误，或 K3s 未启动。

**解决方案**：
1. 检查 `.env` 中的 K3S_HOST/PORT
2. 验证 K3s 可达性：
```bash
curl http://k3s-prod.renew.com:8083/health
```

---

## 5. 配置修改后未生效

**现象**：修改 nginx 配置后行为未变化。

**根因**：未执行 nginx reload。

**解决方案**：
```bash
# 验证配置
docker exec tech-edge-nginx-prod nginx -t

# 热加载
docker exec tech-edge-nginx-prod nginx -s reload
```

---

## 6. 域名匹配优先级问题

**现象**：白名单域名仍可被任意 IP 访问。

**根因**：通配路由优先级高于精确域名路由。

**解决方案**：确保白名单域名使用精确 `server_name`（非正则），nginx 会自动优先匹配精确域名。

```nginx
# 正确：精确域名
server_name admin.prod.web.renew.com;

# 错误：正则匹配
server_name ~^admin\.prod\.web\.renew\.com$;
```

---

## 7. 端口被占用

**现象**：容器启动失败，日志显示 `bind() to 0.0.0.0:443 failed`。

**根因**：80 或 443 端口被其他进程占用。

**解决方案**：
```bash
# 查看端口占用
ss -tlnp | grep -E ":80|:443"

# 停止占用端口的进程
kill <pid>
```

---

## 8. --env 参数传错

**现象**：执行 `/setup-edge-nginx start --env fat` 报错。

**根因**：--env 参数只接受 `nonprod` 或 `prod`。

**解决方案**：
```bash
# 正确
/setup-edge-nginx start --env nonprod
/setup-edge-nginx start --env prod

# 错误
/setup-edge-nginx start --env fat  # 报错
```

---

## 9. 容器名冲突

**现象**：启动新容器时报错 `Conflict. The container name is already in use`。

**根因**：同环境容器已存在。

**解决方案**：
```bash
# 停止并删除旧容器
docker rm -f tech-edge-nginx-prod

# 重新部署
/setup-edge-nginx start --env prod
```

---

## 10. DNS 解析未配置

**现象**：HTTPS 访问超时或无法解析域名。

**根因**：公网 DNS 未配置域名解析到 edge-nginx IP。

**解决方案**：在公网 DNS 服务商配置：
- `*.prod.web.renew.com` → edge-nginx 生产实例 IP
- `*.prod.api.renew.com` → edge-nginx 生产实例 IP

---

## 11. envsubst 吞掉 nginx 内置变量

**现象**：使用 `source .env && envsubst < nginx.conf` 渲染配置后，反代的 `Host` 头丢失，访问日志中 `$remote_addr` 为空，浏览器收到错误页。

**根因**：`envsubst` 会把所有形如 `$VAR` 的字符当成环境变量替换，而 nginx 配置内置了大量 `$host` / `$remote_addr` / `$proxy_add_x_forwarded_for` / `$scheme` / `$request_uri` 等运行时变量。这些变量在环境中未定义，被 `envsubst` 替换为空字符串，配置被彻底破坏。

**解决方案**：edge-nginx / infra-nginx 一律使用 Python 正则替换，仅匹配 `${VAR}` 形式的占位符，不动 nginx 内置 `$host` 等变量。详见 `actions/start.md` Step 5 渲染逻辑。

---

## 12. alpine 镜像无 curl 致 healthcheck 永远 unhealthy

**现象**：`docker ps` 显示 `tech-edge-nginx-${ENV}` 状态为 `unhealthy`，但容器实际正常运行，nginx 可访问。

**根因**：docker-compose.yml healthcheck 用 `curl -sf http://localhost:8888/health`，但 `nginx:1.27-alpine` 镜像默认无 curl（alpine minimal 只带 busybox wget）。

**解决方案**：healthcheck 改用 wget（与 setup-infra-nginx 同款语法）：

```yaml
healthcheck:
  test: ["CMD-SHELL", "wget -qO- http://localhost:8888/health > /dev/null 2>&1 || exit 1"]
```
