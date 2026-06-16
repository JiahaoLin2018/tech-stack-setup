# 踩坑记录 — setup-infra-nginx

> 所有部署中遇到的问题记录于此。问题已在 actions/ 流程或 references/ 配置中修复，本文件仅作历史存档和排障参考。

## [2026-03-31] 远程 envsubst 变量替换失败

- **现象**：远程执行 `source .env && envsubst` 后，`${VAR}` 被替换为空值，nginx 配置变为 `proxy_pass http://:;`，启动失败。
- **根因**：SSH 远程执行时 `source .env` 在子 shell 中运行，环境变量无法传递给后续的 envsubst 命令。
- **修复**：已在 `actions/start.md` 步骤 3 中改为本地 Python 替换变量后再上传配置文件。

## [2026-03-31] nginx 指令重复定义导致启动失败

- **现象**：`nginx: [emerg] "proxy_read_timeout" directive is duplicate in /etc/nginx/conf.d/10-gitlab.conf:14`
- **根因**：`10-gitlab.conf` 中 `include /etc/nginx/proxy_params` 后又设置 `proxy_read_timeout 300s`，与 `proxy_params` 中的 `proxy_read_timeout 60s` 冲突。nginx 的 proxy_* 指令在 location 块中不能重复定义。
- **修复**：已在 `references/conf/nginx/conf.d/10-gitlab.conf` 中对需要自定义超时的服务不使用 `include proxy_params`，直接写完整配置。
- **通用规则**：标准服务用 `include proxy_params`；需自定义超时/缓冲的服务直接写完整配置。

## [2026-04-01] K3s svclb 端口不监听 loopback

- **现象**：`proxy_pass http://127.0.0.1:8083` 返回 502，但用宿主机实际 IP 直连正常。
- **根因**：K3s svclb 通过 iptables PREROUTING DNAT 转发端口，不在宿主机创建 socket 监听。PREROUTING 链只处理外部入站流量，loopback 走 OUTPUT 链，不被 DNAT 捕获。
- **修复**：已在 `references/conf/nginx/conf.d/50-k3s-business.conf` 和 `.env.example` 中将 `proxy_pass` 改为使用 K3s 节点的宿主机实际 IP（`${K3S_NONPROD_TRAEFIK_HOST}` / `${K3S_PROD_TRAEFIK_HOST}`），不用 `127.0.0.1`。

## [2026-04-27] *.prod.web/api 域名误指向非生产 K3s

- **现象**：`50-k3s-business.conf` 把 dev/sit/fat/uat/prod 全部业务域名汇入同一个 server，统一转发到单一变量 `K3S_TRAEFIK_HOST`，而 `setup-k3s-summary` 与 CI/CD pitfalls 都明确该变量"指向非生产 K3s 节点"。结果：内网用户访问 `*.prod.web/api` 实际落到非生产 K3s（错误目标），且物理隔离的生产 K3s 单变量也无法支持。
- **根因**：早期实现只考虑了内网入口对非生产业务流量的转发，未为生产 K3s 留单独的 upstream 变量。
- **修复**：拆分 `50-k3s-business.conf` 为两个 server，分别匹配非生产域名（→ `K3S_NONPROD_TRAEFIK_HOST`）和生产域名（→ `K3S_PROD_TRAEFIK_HOST`）；`.env.example` 把单变量替换为双变量。生产业务流量在 DMZ 由 `setup-edge-nginx --env prod` 处理；infra-nginx 的 prod 域名仅服务内网运维场景，且严格指向独立的生产 K3s。
