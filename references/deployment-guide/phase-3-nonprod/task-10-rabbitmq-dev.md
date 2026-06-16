# Task 10 — RabbitMQ Dev 部署

> 部署 Dev 环境 RabbitMQ（K3s 外部独立 Docker Compose）。对应 architecture-blueprint.md 第五部分阶段三 3-4。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS）+ task-02（infra-nginx，反代 UI 域名） |
| 端口 | :5672（AMQP）/ :15672（管理 UI）/ :15692（Prometheus 内置插件） |
| 反代规则 | infra-nginx 已预配置 `rabbitmq-dev-ui.renew.com` |

## 架构约束

- A 类环境级完全独立
- 默认 `guest` 账户已禁用，必须配置自定义管理员
- 内置 `rabbitmq_prometheus` 插件（无需独立 exporter）
- 推荐使用 Quorum Queue（持久化）

## 关键配置

| 变量 | Dev 值 |
|------|--------|
| `ENV` | `dev` |
| `RABBITMQ_USER` | `admin` 或自定义 |
| `RABBITMQ_PASSWORD` | `<PASS>` |
| 容器内存 | 512m |

## 部署命令

```bash
/setup-rabbitmq start --host <RABBITMQ_DEV_IP> --env dev --user <USER> --password <PASS>
/setup-rabbitmq verify --host <RABBITMQ_DEV_IP> --env dev --user <USER> --password <PASS>
```

## 验证标准

- [ ] `http://rabbitmq-dev-ui.renew.com` 管理 UI 可登录
- [ ] AMQP 直连：`rabbitmq-dev.renew.com:5672` 端口可达
- [ ] `curl http://rabbitmq-dev.renew.com:15692/metrics` 返回 rabbitmq_prometheus 指标
- [ ] 容器名 `tech-rabbitmq-dev` Running

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 512 MB | 1 核 | 50 GB |

## 并行说明

与 Dev 其他中间件（task-07/08/09/11）完全并行。

## 注意事项

- AMQP 协议直连域名需写入 hosts.lan（task-01）
- UI 域名通过 `-ui` 后缀走泛解析→infra-nginx 反代（不写 hosts.lan）
- infra-nginx `41-rabbitmq-ui.conf` 需 `RABBITMQ_DEV_HOST` 变量

## 后续步骤

- 密码记录到 `env/rabbitmq-dev.md`
- task-30 通过 `rabbitmq-dev.renew.com:15692` 抓取 metrics
