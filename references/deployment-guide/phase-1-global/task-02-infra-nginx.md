# Task 02 — infra-nginx 部署

> 部署内网统一流量总闸，**部署前预配置全部反代规则**（含尚未部署的服务）。对应 architecture-blueprint.md 第五部分阶段一 1-2。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS）已完成 |
| DNS 配置 | 本机 DNS 已指向 `<DNS_IP>`，可解析 `*.renew.com` |
| 端口占用 | :80 / :2222 / :8082 必须空闲 |
| 跨机部署 | 必须与 GitLab、Nexus 跨主机部署（`:2222` / `:8082` host 模式透传冲突） |

## 架构约束

- **预配置原则**：部署时一次性配置所有反代规则（含 GitLab/Nexus/Harbor/Apollo/Grafana 等尚未部署的服务），上游不可达返回 502 不影响 nginx 自身运行
- 全局唯一服务，C 类不接受 `--env`
- nginx 静态变量（`$host` / `$remote_addr` 等）严禁 envsubst 渲染（会被吞掉），由 skill 内部用 Python 正则替换 `${SERVICE_HOST}` 类自定义变量

## 预配置反代规则总览

| 类型 | 域名规范 | 后端 |
|------|---------|------|
| HTTP 反代 — 全局唯一 | `gitlab.renew.com` / `nexus.renew.com` / `harbor.renew.com` / `dns.renew.com` | 各自后端 IP:端口 |
| HTTP 反代 — 域级共用 UI | `grafana-{nonprod\|prod}-ui.renew.com` / `prometheus-{nonprod\|prod}-ui.renew.com` / `alertmanager-{nonprod\|prod}-ui.renew.com` | 对应 LGT 后端 |
| HTTP 反代 — 非生产独有 | `apollo.renew.com` | Apollo Portal :8070 |
| HTTP 反代 — 环境级 UI | `consul-{env}-ui.renew.com` / `rabbitmq-{env}-ui.renew.com` | 对应中间件 :8500 / :15672 |
| HTTP 反代 — Apollo Config | `apollo-config-{env}.renew.com` | Apollo Config :8601-8605 |
| HTTP 反代 — 业务应用 | `*.{env}.{web\|api}.renew.com` | K3s Traefik :8083（nonprod / prod 分流） |
| TCP 透传 | `:2222` / `:8082` | GitLab SSH / Nexus Docker Registry |

## 关键 .env 配置（必填占位）

| 变量族 | 说明 |
|------|------|
| `GITLAB_HOST` / `GITLAB_SSH_PORT` | GitLab 反代后端 + SSH 透传 |
| `NEXUS_HOST` / `NEXUS_DOCKER_PORT` | Nexus 反代 + Docker Registry 透传 |
| `HARBOR_HOST` / `DNS_HOST` | Harbor / dnsmasq Web UI 反代 |
| `APOLLO_HOST` / `APOLLO_PROD_HOST` | Apollo Portal + Config（含跨网段生产）|
| `GRAFANA_NONPROD_HOST` / `GRAFANA_PROD_HOST` | LGT UI 反代 |
| `PROMETHEUS_NONPROD_HOST` / `PROMETHEUS_PROD_HOST` | LGT UI 反代 |
| `ALERTMANAGER_NONPROD_HOST` / `ALERTMANAGER_PROD_HOST` | LGT UI 反代 |
| `CONSUL_{DEV,SIT,FAT,UAT,PROD}_HOST` × 5 | 各环境 Consul UI 反代 |
| `RABBITMQ_{DEV,SIT,FAT,UAT,PROD}_HOST` × 5 | 各环境 RabbitMQ UI 反代 |
| `K3S_NONPROD_TRAEFIK_HOST` / `K3S_PROD_TRAEFIK_HOST` / `K3S_TRAEFIK_PORT` | 业务应用反代后端（K3s Traefik :8083，必须用宿主机 IP，不可 127.0.0.1） |

> 全部 `CHANGE_ME_*` 占位符，部署前根据实际拓扑填写。

## 部署命令

```bash
/setup-infra-nginx start --host <NGINX_IP> --user <USER> --password <PASS>
/setup-infra-nginx verify --host <NGINX_IP> --user <USER> --password <PASS>
```

## 验证标准

- [ ] `curl http://gitlab.renew.com -I` 返回 502（GitLab 未部署属正常 — 验证反代规则已就位）
- [ ] `curl http://<NGINX_IP>/health` 返回 `200 OK`
- [ ] `nginx -T` 输出包含全部已知服务的 server 块（GitLab/Nexus/Harbor/Apollo/Grafana 等）
- [ ] `:2222` 和 `:8082` 端口已监听（stream 透传就绪）

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 128 MB | 0.5 核 | 1 GB |

## 注意事项

- 必须与 GitLab / Nexus 跨主机部署（host 模式 `:2222` `:8082` 端口冲突）
- 推荐与 DNS 同机部署（INFRA_NGINX_IP 即为泛解析兜底 IP，简化拓扑）
- nginx 静态变量（`$host` 等）必须用 Python 正则替换，禁止 envsubst（防止吞变量）
- 后续服务部署到位后**无需再修改 infra-nginx**，反代规则已预配置

## 后续步骤

- 继续 task-03（GitLab）/ task-04（Nexus）/ task-05（Harbor），三者无依赖可并行
