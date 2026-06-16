# Task 40 — Consul PROD 部署

> 部署 PROD 环境 Consul（K3s 外部独立 Docker Compose）。对应 architecture-blueprint.md 第五部分阶段四。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS）+ task-02（infra-nginx） |
| 端口 | :8500（HTTP API + UI） / :8600/udp（DNS 接口） |
| 反代规则 | infra-nginx 已预配置 `consul-prod-ui.renew.com` |

## 架构约束

- A 类环境级完全独立
- 单节点模式
- **生产环境必须开启 ACL + Gossip 加密**（编辑 `conf/consul.hcl.tpl` 取消对应注释段；ACL/Gossip 不在 .env 中维护）
- 作为 setup-prometheus consul_sd 的服务发现源
- 业务 Spring Boot 注册时必须打 `metrics` tag

## 关键配置

| 变量 / 配置点 | prod 值 |
|------|--------|
| `CONSUL_ENV`（.env） | `prod` |
| `CONSUL_HTTP_PORT`（.env） | `8500` |
| `CONSUL_DNS_PORT`（.env） | `8600` |
| `CONSUL_LOG_LEVEL`（.env） | `WARN`（dev/sit 排障可改 INFO/DEBUG） |
| ACL 启用（`conf/consul.hcl.tpl`）| 在 `conf/consul.hcl.tpl` 中启用（生产强制） |
| Gossip 加密（`conf/consul.hcl.tpl`）| `consul keygen` 输出（必须） |
| 容器内存 | 512m |

## 部署命令

```bash
/setup-consul start --host <CONSUL_PROD_IP> --env prod --user <USER> --password <PASS>
/setup-consul verify --host <CONSUL_PROD_IP> --env prod --user <USER> --password <PASS>
```

## 验证标准

- [ ] `curl http://consul-prod.renew.com:8500/v1/status/leader` 返回当前 leader
- [ ] `http://consul-prod-ui.renew.com` UI 可访问
- [ ] ACL bootstrap token 已生成并安全保存

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 512 MB | 0.5-1 核 | 20 GB |

## 并行说明

与同环境其他中间件完全并行。

## 注意事项

- 业务 Pod 注册到 Consul 时必须包含 `metrics` tag，否则 task-44 Prometheus consul_sd 不会发现
- infra-nginx `40-consul-ui.conf` 需 `CONSUL_PROD_HOST` 变量

## 后续步骤

- 密码 / Token 记录到 `env/consul-prod.md`
- task-44 通过 `consul-prod.renew.com:8500` 做 consul_sd 发现 spring-boot-prod 服务
