# 踩坑记录 — setup-dns

> 所有部署中遇到的问题记录于此。问题已在 actions/ 流程或 references/ 配置中修复，本文件仅作历史存档和排障参考。

## [2026-03-17] Docker 环境下 dnsmasq 静默丢弃查询（bind-dynamic）

- **现象**：dnsmasq 容器显示 healthy，`ss` 确认 53 端口监听正常，但所有 DNS 查询超时。`tcpdump` 可抓到入站查询包，但 dnsmasq 不产生任何响应，查询日志为空。
- **根因**：两个问题叠加：
  1. CentOS 7 安装 Docker 后未配置 `net.bridge.bridge-nf-call-iptables=1` 和 `net.ipv4.ip_forward=1`，导致容器端口映射虽然存在但流量无法到达容器进程
  2. dnsmasq 默认使用 wildcard socket 监听，收到查询后通过 netlink (`RTM_GETADDR`) 枚举系统网卡，发现 `docker0` 网桥后静默丢弃查询（不报错、不记日志）
- **修复**：已在 `references/dnsmasq.conf` 中配置 `bind-dynamic`，在 `actions/start.md` 第 4 步检查内核参数
- **排障方法**：`strace -p <pid> -e trace=network` 观察是否有 `recvmsg` 无 `sendmsg`；`kill -USR1 <pid>` 查看 `queries answered locally` 是否为 0

## [2026-03-18] bridge 网络模式导致容器 DNS 转发超时

- **现象**：其他 Docker 容器（如 Grafana、Prometheus）无法解析 `*.renew.com` 域名，容器内 DNS 查询超时。
- **根因**：容器通过 Docker 内置 DNS（127.0.0.11）转发查询到宿主机 DNS（dnsmasq），但 dnsmasq 在 bridge 网络模式下通过 docker-proxy 端口映射时 UDP 查询超时。
- **修复**：已在 `references/docker-compose.yml` 中改为 `network_mode: host`，dnsmasq 直接监听宿主机 :53。Web UI 通过 `PORT=5380` 环境变量改为监听 :5380。
