# setup-consul

使用 Docker Compose 部署和管理 Consul 1.20 服务注册与发现，支持多环境独立部署（dev/sit/fat/uat/prod 各一套完全独立实例）。

## 安装

```bash
bash install.sh
```

安装后即可在 Claude Code 中使用 `/setup-consul` 命令。

## 前提条件

- 远程模式：SSH 可连接目标服务器；密码模式需本地安装 `sshpass`

## 支持的命令

| 命令 | 说明 |
|------|------|
| `/setup-consul start --env dev` | 部署 Dev 环境 Consul（默认 env=dev） |
| `/setup-consul stop --env dev` | 停止指定环境 Consul |
| `/setup-consul status --env dev` | 查看指定环境容器状态 |
| `/setup-consul verify --env dev` | 验证集群成员与 API 可达性 |
| `/setup-consul logs --env dev` | 查看容器日志（最近 50 行） |

## 多环境部署

每个环境独立部署，使用独立容器、目录和域名：

| 环境 | 命令 | 部署目录 | 直连域名 | Web UI |
|------|------|---------|---------|--------|
| Dev | `--env dev` | /opt/tech-stack/consul-dev/ | consul-dev.renew.com:8500 | http://consul-dev-ui.renew.com |
| SIT | `--env sit` | /opt/tech-stack/consul-sit/ | consul-sit.renew.com:8500 | http://consul-sit-ui.renew.com |
| FAT | `--env fat` | /opt/tech-stack/consul-fat/ | consul-fat.renew.com:8500 | http://consul-fat-ui.renew.com |
| UAT | `--env uat` | /opt/tech-stack/consul-uat/ | consul-uat.renew.com:8500 | http://consul-uat-ui.renew.com |
| Prod | `--env prod` | /opt/tech-stack/consul-prod/ | consul-prod.renew.com:8500 | http://consul-prod-ui.renew.com |

## 远程部署示例

```bash
# 部署 Dev 环境
/setup-consul start --env dev --host <HOST> --key ~/.ssh/id_rsa

# 部署生产环境（ACL 必须开启）
/setup-consul start --env prod --host <HOST> --key ~/.ssh/id_rsa

# 查看 FAT 环境状态
/setup-consul status --env fat --host <HOST> --key ~/.ssh/id_rsa
```

## .env 配置说明

每个环境在各自部署目录（`/opt/tech-stack/consul-{env}/`）下维护独立的 `.env` 文件：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CONSUL_ENV` | `dev` | 由 start action 自动注入，无需手动修改 |
| `CONSUL_HTTP_PORT` | `8500` | HTTP API 与 UI 端口 |
| `CONSUL_DNS_PORT` | `8600` | DNS 服务端口（UDP） |
| `CONSUL_ENCRYPT_KEY` | `CHANGE_ME_*` | Gossip 加密密钥，通过 `consul keygen` 生成 |
| `CONSUL_ACL_CONFIG` | `# ACL 未启用` | ACL 配置块，生产环境设置为完整 acl 块 |

## Spring Cloud 集成

```yaml
spring:
  cloud:
    consul:
      host: consul-${ENV}.renew.com   # 按部署环境选择，如 consul-dev.renew.com
      port: 8500
      discovery:
        service-name: ${spring.application.name}
        tags: metrics                 # 必填：Prometheus consul_sd 通过此 tag 过滤
        health-check-interval: 10s
```

> 直连域名已写入 `setup-dns/references/hosts.lan`，访问时**必须带端口 8500**。
>
> `tags: metrics` 为强制契约：Prometheus 通过 `consul_sd_configs.tags: ['metrics']` 发现业务服务，未打此 tag 的服务不会被纳入指标抓取。

## 安全加固

- 生产环境必须开启 ACL：在 `.env` 中设置 `CONSUL_ACL_CONFIG` 为完整 acl 配置块
- 生产环境必须设置 Gossip 加密：`CONSUL_ENCRYPT_KEY=<consul keygen 输出>`
- 建议防火墙限制 :8500 仅内网访问

## 配置渲染机制

`consul.hcl.tpl` 是配置模板，启动时通过 `envsubst` 将 `.env` 中的变量（如 `${CONSUL_ENCRYPT_KEY}`、`${CONSUL_ACL_CONFIG}`）渲染为最终的 `consul.hcl`。这确保所有可变配置统一在 `.env` 中管理，无需手动编辑 HCL 文件。

## 目录结构

```
setup-consul/
├── SKILL.md                      # AI 执行指令
├── actions/
│   ├── start.md                  # 启动流程（含 --env 参数处理、envsubst 渲染）
│   ├── stop.md
│   ├── status.md
│   ├── verify.md
│   └── logs.md
├── references/
│   ├── docker-compose.yml        # 生产级配置（容器名含 ${CONSUL_ENV}）
│   ├── .env.example              # 环境变量模板
│   ├── pitfalls.md               # 踩坑记录（含 ACL 启用指南）
│   └── conf/
│       └── consul.hcl.tpl        # Consul 配置模板（envsubst 渲染）
├── README.md
└── install.sh
```

## 注意事项

- 首次启动约需 5-10 秒完成初始化
- 数据持久化在各环境工作目录的 `data/` 子目录中
- 各环境完全独立，不通过 Tags 共享实例
