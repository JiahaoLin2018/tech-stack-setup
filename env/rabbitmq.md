# RabbitMQ 4.0 — 部署报告

| 项目 | 值 |
|------|-----|
| 部署日期 | 2026-03-18 |
| 目标机器 | 192.168.82.93 (Server A) |
| 部署目录 | `/opt/tech-stack/rabbitmq/` |
| 容器名称 | tech-rabbitmq |
| 镜像 | rabbitmq:4.0-management-alpine |
| 版本 | RabbitMQ 4.0.9 |

## 端口

| 端口 | 用途 |
|------|------|
| 5672 | AMQP 协议（业务消息） |
| 15672 | Management Web UI |
| 15692 | Prometheus 指标 |

## 账号密码

| 用户 | 密码 | 权限 |
|------|------|------|
| admin | RmqAdm_eLO9Px54fJtygGvI | administrator（全部） |

## 连接方式

| 方式 | 地址 |
|------|------|
| AMQP URI | `amqp://admin:RmqAdm_eLO9Px54fJtygGvI@rabbitmq.renew.com:5672/` |
| Management UI | http://rabbitmq.renew.com:15672 (admin / RmqAdm_eLO9Px54fJtygGvI) |
| Spring Boot | `spring.rabbitmq.host=rabbitmq.renew.com`<br>`spring.rabbitmq.port=5672`<br>`spring.rabbitmq.username=admin`<br>`spring.rabbitmq.password=RmqAdm_eLO9Px54fJtygGvI` |
| Prometheus | http://rabbitmq.renew.com:15692/metrics |

## 配置

| 参数 | 值 |
|------|-----|
| 内存高水位 | 40% |
| 磁盘空闲低水位 | 2GB |
| heartbeat | 60s |
| 插件 | rabbitmq_management, rabbitmq_prometheus |

## 备注

- 内置 Prometheus 指标插件（rabbitmq_prometheus），无需额外 exporter 容器
- Management UI 可直接通过 `rabbitmq.renew.com:15672` 访问
