# Task 06 — 部署 RabbitMQ

- **状态**: ✅ 完成
- **目标机器**: 192.168.82.93
- **Skill**: setup-rabbitmq
- **前置依赖**: Task 02 (DNS)
- **内存预算**: 512M

## 执行内容

1. 执行 `/setup-rabbitmq start` 部署 RabbitMQ 4.0
2. 修改默认账号密码
3. 验证管理界面和连接

## Skill 命令

```bash
/setup-rabbitmq start --host 192.168.82.93 --user root --password foxconn.88
/setup-rabbitmq verify --host 192.168.82.93 --user root --password foxconn.88
```

## 端口说明

- `:5672` — AMQP 协议端口
- `:15672` — 管理界面
- `:15692` — Prometheus 指标端口

## 验证标准

- [ ] RabbitMQ 容器运行中
- [ ] 管理界面 `rabbitmq.renew.com:15672` 可访问
- [ ] `:15692` Metrics 端点可访问

## 完成记录

- 开始时间:
- 完成时间:
- 备注:
