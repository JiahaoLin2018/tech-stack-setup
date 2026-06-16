# Task 05 — 部署 MongoDB

- **状态**: ✅ 完成
- **目标机器**: 192.168.82.93
- **Skill**: setup-mongodb
- **前置依赖**: Task 02 (DNS)
- **内存预算**: 2G

## 执行内容

1. 执行 `/setup-mongodb start` 部署 MongoDB 8.0
2. 修改默认密码
3. 限制 WiredTiger cache 为 1G（默认会占 50% 物理内存）
4. 验证连接

## Skill 命令

```bash
/setup-mongodb start --host 192.168.82.93 --user root --password foxconn.88
/setup-mongodb verify --host 192.168.82.93 --user root --password foxconn.88
```

## 内存调优要点

- `wiredTigerCacheSizeGB: 1`（严格限制，默认 50% 物理内存会吃掉 7.5G）
- MongoDB Exporter 随 MongoDB 一起部署（:9216）

## 验证标准

- [ ] MongoDB 容器运行中
- [ ] 可通过 `mongodb.renew.com:27017` 连接
- [ ] MongoDB Exporter `:9216` 可访问

## 完成记录

- 开始时间:
- 完成时间:
- 备注:
