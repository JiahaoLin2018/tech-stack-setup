# Task 19 — DNS 配置更新

- **状态**: ✅ 已完成
- **目标机器**: 192.168.82.93
- **Skill**: `/setup-dns`
- **前置依赖**: Task 18（infra-nginx 部署完成）

## 目标

infra-nginx 部署完成后，更新 dnsmasq 配置，使整套域名寻址体系生效：

1. **`dnsmasq.conf` 追加泛解析** — 所有未在 hosts.lan 中定义的 `*.renew.com` 自动解析到 93（infra-nginx）
2. **`hosts.lan` 重新整理** — 只保留区一（基础设施直连），移除历史残留条目

## 两层解析机制说明

```
dnsmasq 解析优先级：hosts.lan 精确匹配 > dnsmasq.conf 泛解析

区一（hosts.lan 精确映射）：
  mysql / redis / mongodb / rabbitmq / consul / otel / tempo / loki / prometheus
  → 微服务 / OTel Collector 直连，多机部署时各有不同 IP，必须精确指定

区二（dnsmasq.conf 泛解析兜底，不写 hosts.lan）：
  grafana / gitlab / nexus / harbor / alertmanager / consul-ui / apollo-portal / rabbitmq-mgmt / dns-ui ...
  → 全部解析到 93，由 infra-nginx 按域名反代，新增服务无需改 hosts.lan

业务域名（不在 dnsmasq 维护）：
  *.fat.web.renew.com / *.fat.api.renew.com ...
  → 测试：开发者本机 hosts 文件（→ 97）；生产：公网 DNS A 记录（→ 97）
```

## Step 1：更新 dnsmasq.conf（追加泛解析）

在 `/opt/tech-stack/dns/dnsmasq.conf` 末尾追加：

```conf
# ============================================================
# 泛解析兜底：所有未在 hosts.lan 中定义的 *.renew.com → infra-nginx（93:80）
#
# 覆盖范围：grafana / gitlab / nexus / harbor 等所有内部 Web UI 域名
# 解析优先级：hosts.lan 精确匹配 > 此泛解析（区一不受影响）
# ============================================================
address=/.renew.com/192.168.82.93
```

```bash
ssh root@192.168.82.93
cat >> /opt/tech-stack/dns/dnsmasq.conf << 'EOF'

# 泛解析兜底：所有未在 hosts.lan 中定义的 *.renew.com → infra-nginx（93:80）
address=/.renew.com/192.168.82.93
EOF
```

## Step 2：重写 hosts.lan（只保留区一）

用以下内容完整替换 `/opt/tech-stack/dns/hosts.lan`：

```
# tech-stack 局域网域名映射 — 区一（基础设施直连）
#
# 职责说明：
#   此文件只维护需要"精确指定 IP"的基础设施域名。
#   内部 Web UI（grafana/gitlab/nexus 等）由 dnsmasq.conf 泛解析自动兜底，无需写此文件。
#   业务域名（*.fat.web.renew.com 等）不在此维护。
#
# 修改后重启生效：docker restart tech-dns
# 多机扩展：将对应域名的 IP 改为目标机器的实际 IP

# ========== 数据存储层 ==========
192.168.82.93  mysql.renew.com
192.168.82.93  redis.renew.com
192.168.82.93  mongodb.renew.com

# ========== 消息中间件层 ==========
192.168.82.93  rabbitmq.renew.com

# ========== 服务治理层 ==========
192.168.82.93  consul.renew.com
# Apollo Config Service: apollo-config-{env}.renew.com 由泛解析 → infra-nginx 代理，无需精确记录

# ========== 可观测性层 ==========
192.168.82.93  otel.renew.com
192.168.82.93  tempo.renew.com
192.168.82.93  loki.renew.com
192.168.82.93  prometheus.renew.com
```

```bash
# 完整替换 hosts.lan（不是追加）
cat > /opt/tech-stack/dns/hosts.lan << 'EOF'
# tech-stack 局域网域名映射 — 区一（基础设施直连）
# 修改后重启生效：docker restart tech-dns

# ========== 数据存储层 ==========
192.168.82.93  mysql.renew.com
192.168.82.93  redis.renew.com
192.168.82.93  mongodb.renew.com

# ========== 消息中间件层 ==========
192.168.82.93  rabbitmq.renew.com

# ========== 服务治理层 ==========
192.168.82.93  consul.renew.com
# Apollo Config Service: apollo-config-{env}.renew.com 由泛解析 → infra-nginx 代理，无需精确记录

# ========== 可观测性层 ==========
192.168.82.93  otel.renew.com
192.168.82.93  tempo.renew.com
192.168.82.93  loki.renew.com
192.168.82.93  prometheus.renew.com
EOF
```

## Step 3：重启 dnsmasq

```bash
docker restart tech-dns

# 确认容器正常运行
docker ps --filter name=tech-dns --format "table {{.Names}}\t{{.Status}}"
```

## 验证清单

```bash
# 区一：精确匹配，解析到服务实际所在机器
dig mysql.renew.com @192.168.82.93 +short      # 应返回 192.168.82.93
dig consul.renew.com @192.168.82.93 +short     # 应返回 192.168.82.93
dig tempo.renew.com @192.168.82.93 +short      # 应返回 192.168.82.93

# 区二：泛解析兜底，解析到 93（infra-nginx）
dig grafana.renew.com @192.168.82.93 +short    # 应返回 192.168.82.93（泛解析）
dig gitlab.renew.com @192.168.82.93 +short     # 应返回 192.168.82.93（泛解析）
dig harbor.renew.com @192.168.82.93 +short     # 应返回 192.168.82.93（泛解析）

# 泛解析通用验证：任意未定义的 *.renew.com 域名都应兜底
dig unknown-service.renew.com @192.168.82.93 +short  # 应返回 192.168.82.93

# 公网域名：正常转发上游 DNS
dig baidu.com @192.168.82.93 +short            # 应返回公网 IP（非 192.168.82.x）

# 端对端验证（通过 infra-nginx）：需要开发者电脑已将 DNS 指向 dnsmasq
curl -sf http://grafana.renew.com/api/health   # 应返回 {"database":"ok",...}
curl -sf http://harbor.renew.com               # 应返回 Harbor 登录页 HTML
```

- [ ] `mysql.renew.com` → 192.168.82.93（区一精确匹配）
- [ ] `grafana.renew.com` → 192.168.82.93（区二泛解析）
- [ ] `gitlab.renew.com` → 192.168.82.93（区二泛解析）
- [ ] `unknown.renew.com` → 192.168.82.93（泛解析兜底生效）
- [ ] `baidu.com` → 公网 IP（上游 DNS 转发正常）
- [ ] `http://grafana.renew.com` 浏览器可访问（infra-nginx 代理正常）

## 完成记录

- 开始时间: 2026-03-31
- 完成时间: 2026-03-31
- 备注:
  - dnsmasq.conf 已包含泛解析配置 `address=/.renew.com/192.168.82.93`
  - hosts.lan 已重写，只保留区一（基础设施直连）域名
  - DNS 解析验证通过：
    - 区一精确匹配：mysql/consul/tempo -> 192.168.82.93
    - 区二泛解析：grafana/gitlab/harbor/unknown -> 192.168.82.93
    - 上游转发：baidu.com -> 公网 IP
  - 端对端验证通过：Grafana/Prometheus/Consul/RabbitMQ/Apollo/GitLab HTTP 均可访问
  - Harbor 正在部署中，待完成后验证
