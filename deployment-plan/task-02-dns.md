# Task 02 — 部署 DNS (dnsmasq)

- **状态**: ✅ 完成（Docker 容器部署）
- **目标机器**: 192.168.82.93
- **Skill**: setup-dns
- **前置依赖**: Task 00 (Docker on 93)

## 重要性

> DNS 是整个架构的基石，必须最先部署。所有服务通过 `*.renew.com` 域名寻址。

## 执行内容

1. 执行 `/setup-dns start` 在 93 上部署 dnsmasq
2. 配置 `hosts.lan` 域名映射（见下方）
3. 在 93 和 97 两台机器上配置 DNS 指向 93
4. 验证域名解析

## hosts.lan 配置

```
192.168.82.93   dns.renew.com
192.168.82.93   mysql.renew.com
192.168.82.93   redis.renew.com
192.168.82.93   mongodb.renew.com
192.168.82.93   rabbitmq.renew.com
192.168.82.93   consul.renew.com
# apollo-config-{env}.renew.com 由泛解析 → infra-nginx 代理，无需精确记录
192.168.82.93   otel.renew.com
192.168.82.93   tempo.renew.com
192.168.82.93   loki.renew.com
192.168.82.93   prometheus.renew.com
192.168.82.93   grafana.renew.com
192.168.82.93   gateway.renew.com
192.168.82.93   harbor.renew.com
192.168.82.97   gitlab.renew.com
# nexus.renew.com 通过泛解析 → 93(infra-nginx) 代理，无需精确记录
```

## Skill 命令

```bash
/setup-dns start --host 192.168.82.93 --user root --password foxconn.88

# 配置 hosts.lan 后，在两台机器上配置 DNS 指向
/setup-dns configure --host 192.168.82.93 --user root --password foxconn.88
/setup-dns configure --host 192.168.82.97 --user root --password foxconn.88

# 验证
/setup-dns verify --host 192.168.82.93 --user root --password foxconn.88
```

## 验证标准

- [ ] dnsmasq 容器运行中
- [ ] `nslookup mysql.renew.com` 解析到 192.168.82.93
- [ ] `nslookup gitlab.renew.com` 解析到 192.168.82.97
- [ ] 两台机器都能正常解析 `*.renew.com`

## 完成记录

- 开始时间:
- 完成时间:
- 备注:
