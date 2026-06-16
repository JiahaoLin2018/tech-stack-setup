# Task 25 — RabbitMQ UAT 部署

> 部署 UAT 环境 RabbitMQ（K3s 外部独立 Docker Compose）。对应 architecture-blueprint.md 第五部分阶段三。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS）+ task-02（infra-nginx） |
| 端口 | :5672（AMQP）/ :15672（管理 UI）/ :15692（Prometheus 内置插件） |
| 反代规则 | infra-nginx 已预配置 `rabbitmq-uat-ui.renew.com` |

## 架构约束

- A 类环境级完全独立
- 默认 `guest` 账户已禁用，必须配置自定义管理员
- 内置 `rabbitmq_prometheus` 插件（无需独立 exporter）
- 推荐 Quorum Queue（持久化）

## 关键配置

| 变量 | uat 值 |
|------|--------|
| `ENV` | `uat` |
| `RABBITMQ_USER` | `admin` 或自定义 |
| `RABBITMQ_PASSWORD` | `<PASS>` |
| 容器内存 | 1g |

## 部署命令

```bash
/setup-rabbitmq start --host <RABBITMQ_UAT_IP> --env uat --user <USER> --password <PASS>
/setup-rabbitmq verify --host <RABBITMQ_UAT_IP> --env uat --user <USER> --password <PASS>
```

## 验证标准

- [ ] `http://rabbitmq-uat-ui.renew.com` 管理 UI 可登录
- [ ] AMQP 直连：`rabbitmq-uat.renew.com:5672` 端口可达
- [ ] `curl http://rabbitmq-uat.renew.com:15692/metrics` 返回 rabbitmq_prometheus 指标

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 1g | 1-2 核 | 50 GB |

## 并行说明

与同环境其他中间件完全并行。

## 注意事项

- AMQP 域名走 hosts.lan，UI 域名走泛解析→infra-nginx
- infra-nginx `41-rabbitmq-ui.conf` 需 `RABBITMQ_UAT_HOST` 变量

## 后续步骤

- 密码记录到 `env/rabbitmq-uat.md`
- task-30 通过 `rabbitmq-uat.renew.com:15692` 抓取 metrics
