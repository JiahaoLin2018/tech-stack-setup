# Task 07 — MySQL Dev 部署

> 部署 Dev 环境业务 MySQL（K3s 外部独立 Docker Compose）。对应 architecture-blueprint.md 第五部分阶段三 3-1。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS）已完成，hosts.lan 含 `mysql-dev.renew.com` |
| 环境要求 | Docker + Docker Compose；本机 DNS 指向 `<DNS_IP>` |
| 端口 | :3306（业务直连）/ :9104（mysqld_exporter） |

## 架构约束

- A 类环境级完全独立，与其他 4 套 MySQL 无任何数据交集
- K3s 外部独立部署，业务 Pod 通过域名直连
- 与 Apollo 专用 MySQL（task-06 内置）完全分离
- 内置 mysqld_exporter v0.16.0 sidecar，密码三处一致性由 actions/start.md 强制校验

## 关键配置

| 变量 | Dev 值 |
|------|--------|
| `ENV` | `dev` |
| `MYSQL_ROOT_PASSWORD` | `<PASS>`（按 `MysRoot_{16位随机}` 规则）|
| `MYSQL_APP_PASSWORD` | 业务用户密码 |
| `MYSQL_EXPORTER_PASSWORD` | exporter 用户密码（三处必须一致：.env / exporter.my.cnf / init SQL） |
| `MYSQL_INNODB_BUFFER_POOL` | `700M`（容器内存 70%） |
| 容器内存 | 1g |

## 部署命令

```bash
/setup-mysql start --host <MYSQL_DEV_IP> --env dev --user <USER> --password <PASS>
/setup-mysql verify --host <MYSQL_DEV_IP> --env dev --user <USER> --password <PASS>
```

## 验证标准

- [ ] `mysql -h mysql-dev.renew.com -P 3306 -u appuser -p<APP_PASS>` 可连接
- [ ] `curl http://mysql-dev.renew.com:9104/metrics` 返回 mysqld_exporter 指标
- [ ] 容器名 `tech-mysql-dev` + `tech-mysql-exporter-dev` 全部 Running
- [ ] DNS 解析正常：`nslookup mysql-dev.renew.com` 返回 `<MYSQL_DEV_IP>`

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 1 GB | 1 核 | 100 GB |

## 并行说明

- 与 task-08（Redis Dev）/ task-09（MongoDB Dev）/ task-10（RabbitMQ Dev）/ task-11（Consul Dev）完全并行
- 与 task-12~26（SIT/FAT/UAT 中间件）跨机器并行

## 注意事项

- root 账号默认仅 localhost 登录，远程必须用 `appuser` 或 `exporter` 用户
- exporter 三处密码不一致会启动失败（actions/start.md 步骤 6b 自动校验）
- init SQL 不创建业务库，由应用按 Apollo 配置创建

## 后续步骤

- 密码记录到 `env/mysql-dev.md`（禁止入 git）
- task-30（Prometheus nonprod）会通过 `mysql-dev.renew.com:9104` 抓取 metrics 并打 `env=dev` 标签
