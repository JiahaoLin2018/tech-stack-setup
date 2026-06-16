# DNS (dnsmasq) — 部署报告


| 项目   | 值                        |
| ---- | ------------------------ |
| 部署日期 | 2026-03-17               |
| 密码更新 | 2026-03-18               |
| 目标机器 | 192.168.82.93 (Server A) |
| 部署目录 | `/opt/tech-stack/dns/`   |
| 容器名称 | tech-dns                 |
| 镜像   | jpillora/dnsmasq:latest  |


## 端口


| 端口   | 协议      | 用途       |
| ---- | ------- | -------- |
| 53   | TCP/UDP | DNS 服务   |
| 5380 | TCP     | Web 管理界面 |


## 账号密码


| 用途     | 用户名   | 密码                      |
| ------ | ----- | ----------------------- |
| Web UI | admin | DnsAdm_ApiUY3qujoe9B0Qo |


## 连接方式


| 方式       | 地址                                                     |
| -------- | ------------------------------------------------------ |
| DNS 查询   | `dns.renew.com:53`                                     |
| Web 管理界面 | [http://dns.renew.com:5380](http://dns.renew.com:5380) |


## 备注

- dnsmasq.conf 必须包含 `bind-dynamic` 以兼容 Docker 环境
- 宿主机需配置内核参数 `net.bridge.bridge-nf-call-iptables=1`

