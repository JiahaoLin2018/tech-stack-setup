# Task 10 — 部署 Loki

- **状态**: ✅ 完成
- **目标机器**: 192.168.82.93
- **Skill**: setup-loki
- **前置依赖**: Task 02 (DNS)
- **内存预算**: 1G

## 执行内容

1. 执行 `/setup-loki start` 部署 Loki 3.5.0
2. 验证服务健康

## Skill 命令

```bash
/setup-loki start --host 192.168.82.93 --user root --password foxconn.88
/setup-loki verify --host 192.168.82.93 --user root --password foxconn.88
```

## 端口说明

- `:3100` — HTTP API（接收日志推送 + Grafana 数据源）

## 验证标准

- [ ] Loki 容器运行中
- [ ] `loki.renew.com:3100/ready` 返回 ready

## 完成记录

- 开始时间:
- 完成时间:
- 备注:
