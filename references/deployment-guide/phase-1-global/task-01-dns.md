# Task 01 — DNS 部署

> 建立内网统一域名解析中心，所有服务的基石。对应 architecture-blueprint.md 第五部分阶段一 1-1。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | 无（第一个部署） |
| 环境要求 | Docker + Docker Compose 已安装 |
| 端口占用 | :53 必须空闲（Ubuntu 需先停 systemd-resolved 或限制其监听） |
| 内核参数 | `net.bridge.bridge-nf-call-iptables=1`、`net.ipv4.ip_forward=1` |

## 架构约束

- DNS 是整个架构的基石，必须最先部署
- `network_mode: host` 必启（bridge 模式 UDP 转发超时）
- `bind-dynamic` 必启（避免 Docker 网桥导致静默丢弃查询）
- hosts.lan 需预规划全部直连域名 → IP 映射（37 条必备）

## hosts.lan 预规划清单（必备 37 条）

```
# ====== ④ 环境级直连 — 5 服务 × 5 环境 = 25 条 ======
<IP>   mysql-{dev,sit,fat,uat,prod}.renew.com
<IP>   redis-{dev,sit,fat,uat,prod}.renew.com
<IP>   mongodb-{dev,sit,fat,uat,prod}.renew.com
<IP>   rabbitmq-{dev,sit,fat,uat,prod}.renew.com
<IP>   consul-{dev,sit,fat,uat,prod}.renew.com

# ====== ② 域级直连 — 6 服务 × 2 域 = 12 条 ======
<IP>   otel-{nonprod,prod}.renew.com
<IP>   loki-{nonprod,prod}.renew.com
<IP>   tempo-{nonprod,prod}.renew.com
<IP>   prometheus-{nonprod,prod}.renew.com
<IP>   alertmanager-{nonprod,prod}.renew.com
<IP>   k3s-{nonprod,prod}.renew.com
```

> 不写入 hosts.lan 的域名（gitlab/nexus/harbor/dns/apollo/grafana-*-ui 等）由 dnsmasq 泛解析 `address=/.renew.com/<INFRA_NGINX_IP>` 兜底到 infra-nginx。

## 关键 .env 配置

| 变量 | 说明 |
|------|------|
| `INFRA_NGINX_IP` | 泛解析兜底目标，未在 hosts.lan 精确匹配的 `*.renew.com` 域名解析至此 |
| `DNS_WEB_PORT` | `5380`（Web UI 端口） |
| `DNS_WEB_USER` / `DNS_WEB_PASSWORD` | Web UI 登录凭证（`DnsAdm_{16位随机}` 规则） |
| `UPSTREAM_DNS_PRIMARY` | 公网域名上游 DNS（默认 `114.114.114.114`，按地域调整） |
| `UPSTREAM_DNS_SECONDARY` | 公网域名备用 DNS（默认 `8.8.8.8`） |

> dnsmasq 监听 :53（host 网络模式固定）；本机 IP 由 setup-dns 自动获取无需配置。
> dnsmasq 节点 IP 作为 `DNS_SERVER_IP` 由 setup-k3s 等下游消费方在各自 .env 中填写。

## 部署命令

```bash
/setup-dns start --host <DNS_IP> --user <USER> --password <PASS>
/setup-dns verify --host <DNS_IP> --user <USER> --password <PASS>
```

## 验证标准

- [ ] `nslookup mysql-dev.renew.com <DNS_IP>` 返回 hosts.lan 中配置的 IP
- [ ] `nslookup grafana-nonprod-ui.renew.com <DNS_IP>` 返回 `INFRA_NGINX_IP`
- [ ] `nslookup baidu.com <DNS_IP>` 通过上游 DNS 正常解析
- [ ] `dns.renew.com` Web UI 可访问（部署后由 infra-nginx 反代）
- [ ] `hosts.lan` 至少 37 条必备直连域名

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 128 MB | 0.1 核 | 1 GB |

## 注意事项

- Ubuntu/Debian：systemd-resolved 默认占用 :53，需 `systemctl stop systemd-resolved` 或修改其配置仅监听 127.0.0.53
- `network_mode: host` 必启，否则 UDP 转发超时（详见 setup-dns/references/pitfalls.md）
- hosts.lan 变更后需 `docker restart tech-dns` 才生效
- 推荐与 infra-nginx 同机部署（INFRA_NGINX_IP = DNS_SERVER_IP，简化网络规划）

## 后续步骤

- 所有服务器（含本机）DNS 配置指向 `<DNS_IP>`：
  - Linux：`/etc/resolv.conf` 写 `nameserver <DNS_IP>`
  - 或通过 `/setup-dns configure --host <目标机器IP> --dns-server <DNS_IP> --user <USER> --password <PASS>` 自动处理 systemd-resolved / NetworkManager / resolv.conf
- 继续 task-02（infra-nginx）
