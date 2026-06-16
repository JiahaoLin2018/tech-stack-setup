# Task 03 — 部署 MySQL

- **状态**: ✅ 完成
- **目标机器**: 192.168.82.93
- **Skill**: setup-mysql
- **前置依赖**: Task 02 (DNS)
- **内存预算**: 2G

## 执行内容

1. 执行 `/setup-mysql start` 部署 MySQL 8.4
2. 修改默认密码（替换 `CHANGE_ME_*` 占位符）
3. 内存限制：innodb_buffer_pool_size 控制在 1G 以内（15G 机器资源有限）
4. 验证连接

## Skill 命令

```bash
/setup-mysql start --host 192.168.82.93 --user root --password foxconn.88
/setup-mysql verify --host 192.168.82.93 --user root --password foxconn.88
```

## 内存调优要点

- `innodb_buffer_pool_size = 1G`（常规建议 70% 物理内存，但本机混部需限制）
- MySQL Exporter 随 MySQL 一起部署，供 Prometheus 采集指标（:9104）

## 验证标准

- [ ] MySQL 容器运行中
- [ ] 可通过 `mysql.renew.com:3306` 连接
- [ ] MySQL Exporter `:9104` 可访问

## 完成记录

- 开始时间:
- 完成时间:
- 备注:
