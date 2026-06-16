# 踩坑记录 — setup-rabbitmq

> 部署中遇到的具体问题、版本约束和决策原因记录于此。SKILL.md / actions / README 只描述"现在怎么做"，根因和历史脉络放在这里。

## RabbitMQ 4.0 与 Classic Mirrored Queue

RabbitMQ 4.0 已彻底移除 Classic Mirrored Queue（经典镜像队列）。从 3.x 升级或新接入的业务代码必须使用 Quorum Queue：

- 声明队列时显式传 `x-queue-type: quorum`
- Spring AMQP 4.x 在 `Queue` 定义中通过 `withArguments(Map.of("x-queue-type", "quorum"))` 设置
- 旧代码若仍声明 `x-ha-policy` 等镜像队列参数，启动时会被忽略（不会报错），但消息不会持久复制 → 节点宕机即丢

## guest 账户

`rabbitmq:4.0-management-alpine` 镜像默认禁止 guest 账户从非 localhost 登录（`loopback_users.guest = true`）。业务连接必须使用 `RABBITMQ_DEFAULT_USER/PASS` 注入的自定义管理员，不能依赖 guest。

## 内存与磁盘水位

- `vm_memory_high_watermark.relative = 0.4`：触发阈值是**容器内存上限**的 40%，不是宿主机总内存
- `disk_free_limit.absolute = 2GB`：磁盘剩余低于 2GB 时阻塞发布
- 容器配额（`RABBITMQ_MEMORY_LIMIT`）调整后水位会按比例联动

## Prometheus 指标端点

`rabbitmq_prometheus` 插件内置在 `4.0-management-alpine` 镜像中，无需额外 exporter 容器。指标路径是 `/metrics`（不是 Spring Boot 的 `/actuator/prometheus`）。

## 多环境与 vhost

各环境部署完全独立的物理实例（5 套），实例之间没有任何数据交集，业务用默认 vhost `/` 即可。
`init/01_init_env_vhosts.sh` 仅用于"同一实例内多应用切分 vhost"这种少见场景，不要用它做环境隔离。
