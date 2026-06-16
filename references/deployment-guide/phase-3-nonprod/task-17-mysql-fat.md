# Task 17 — MySQL FAT 部署

> 部署 FAT 环境业务 MySQL（K3s 外部独立 Docker Compose）。对应 architecture-blueprint.md 第五部分阶段三。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS）已完成，hosts.lan 含 `mysql-fat.renew.com` |
| 环境要求 | Docker + Docker Compose；本机 DNS 指向 `<DNS_IP>` |
| 端口 | :3306（业务直连）/ :9104（mysqld_exporter） |

## 架构约束

- A 类环境级完全独立，与其他 4 套 MySQL 无任何数据交集
- K3s 外部独立部署，业务 Pod 通过域名直连
- 与 Apollo 专用 MySQL（task-06 / task-47 内置）完全分离

## 关键配置

| 变量 | fat 值 |
|------|--------|
| `ENV` | `fat` |
| `MYSQL_ROOT_PASSWORD` | `<PASS>` |
| `MYSQL_INNODB_BUFFER_POOL` | `1.4G`（容器内存 70%）|
| 容器内存 | 2g |

## 部署命令

```bash
/setup-mysql start --host <MYSQL_FAT_IP> --env fat --user <USER> --password <PASS>
/setup-mysql verify --host <MYSQL_FAT_IP> --env fat --user <USER> --password <PASS>
```

## 验证标准

- [ ] `mysql -h mysql-fat.renew.com -P 3306 -u appuser -p<APP_PASS>` 可连接
- [ ] `curl http://mysql-fat.renew.com:9104/metrics` 返回 mysqld_exporter 指标
- [ ] 容器名 `tech-mysql-fat` + `tech-mysql-exporter-fat` 全部 Running

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 2g | 1-2 核 | 100 GB |

## 并行说明

- 与同环境其他中间件（Redis / MongoDB / RabbitMQ / Consul）完全并行
- 与其他环境的中间件跨机器并行

## 注意事项

- exporter 三处密码必须一致（actions/start.md 步骤 6b 自动校验）


## 后续步骤

- 密码记录到 `env/mysql-fat.md`（禁止入 git）
- task-30（Prometheus nonprod）通过 `mysql-fat.renew.com:9104` 抓取 metrics 并打 `env=fat` 标签
