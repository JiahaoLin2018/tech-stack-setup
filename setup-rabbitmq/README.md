# setup-rabbitmq — RabbitMQ 4.0 生产级部署

使用 Docker Compose 在本地或远程服务器上部署生产级 RabbitMQ 4.0（含 Management UI），包含内存高水位保护、磁盘空闲限制和日志级别控制。

## 简介

| 项目 | 内容 |
|------|------|
| 镜像版本 | rabbitmq:4.0-management-alpine |
| 容器名称 | tech-rabbitmq-{env} |
| AMQP 端口 | 5672 |
| Management UI 端口 | 15672 |
| Prometheus 指标端口 | 15692 |
| 持久化目录（远程） | `/opt/tech-stack/rabbitmq-{env}/data` |

## 目录结构

```
setup-rabbitmq/
├── SKILL.md                        # 路由指令（Claude AI 读取）
├── actions/
│   ├── start.md                    # 完整启动流程（含本地/远程两种模式）
│   ├── stop.md
│   ├── status.md
│   ├── verify.md
│   └── logs.md
├── references/
│   ├── docker-compose.yml          # 生产级配置
│   ├── .env.example                # 环境变量模板
│   └── conf/
│       ├── rabbitmq.conf           # RabbitMQ 生产优化配置
│       └── enabled_plugins         # 启用插件列表（management + prometheus）
├── README.md
└── install.sh
```

## 安装步骤

在 tech-stack-setup 仓库根目录下运行：

```bash
bash setup-rabbitmq/install.sh
```

脚本将 `setup-rabbitmq/` 全部内容复制到 `~/.claude/skills/setup-rabbitmq/`。

## 部署示例

### 密码认证

```
/setup-rabbitmq start --host <HOST> --user ubuntu --password mySSHpassword
```

### SSH Key 认证

```
/setup-rabbitmq start --host <HOST> --user ubuntu --key ~/.ssh/id_rsa
```

### 指定非标准 SSH 端口

```
/setup-rabbitmq start --host <HOST> --user ubuntu --key ~/.ssh/id_rsa --ssh-port 2222
```

## .env 配置说明

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `RABBITMQ_USER` | admin | 管理员用户名 |
| `RABBITMQ_PASSWORD` | 无（必填） | 管理员密码，最少 16 位 |
| `RABBITMQ_VHOST` | / | 默认 Virtual Host |
| `RABBITMQ_AMQP_PORT` | 5672 | AMQP 协议端口 |
| `RABBITMQ_MGMT_PORT` | 15672 | Management UI 端口 |
| `RABBITMQ_PROMETHEUS_PORT` | 15692 | Prometheus 指标端口 |
| `RABBITMQ_MEMORY_LIMIT` | 1g | 容器内存上限 |
| `RABBITMQ_MEMORY_RESERVATION` | 256m | 容器内存预留 |
| `TZ` | Asia/Shanghai | 容器时区 |

## 生产注意事项

1. **密码强度**：必须替换 `CHANGE_ME_*` 占位符，建议使用 16 位以上随机字符串
2. **Quorum Queue**：生产环境必须使用 Quorum Queue 实现消息持久化与节点容灾，Spring AMQP 4.x 通过 `x-queue-type: quorum` 参数声明
3. **内存水位**：`rabbitmq.conf` 中 `vm_memory_high_watermark.relative = 0.4` 表示超过系统内存 40% 时开始阻塞发布者；若容器内存上限为 1g，则约 400MB 时触发，可通过 `.env` 中 `RABBITMQ_MEMORY_LIMIT` 调整容器上限
4. **磁盘水位**：`disk_free_limit.absolute = 2GB` 表示磁盘剩余空间低于 2GB 时触发保护，请确保磁盘充足
5. **Management UI 安全**：生产环境强烈建议通过 nginx 反向代理并启用 HTTPS，不要直接暴露 15672 端口
6. **端口安全**：5672 端口仅对内网应用开放，15672 端口通过反向代理访问，15692 端口仅对 Prometheus 开放
7. **Prometheus 指标**：已内置 `rabbitmq_prometheus` 插件，暴露 15692 端口供 Prometheus 采集，指标端点 `http://<host>:15692/metrics`
8. **vhost 隔离**：建议为不同应用创建独立 vhost，避免队列名冲突
9. **停止顺序**：stop action 会先执行 `rabbitmqctl stop_app` 进行优雅停止，确保处理中的消息完成
