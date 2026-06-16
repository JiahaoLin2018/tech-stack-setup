# Task 09 — 部署 Tempo

- **状态**: ⬜ 待执行
- **目标机器**: 192.168.82.93
- **Skill**: setup-tempo
- **前置依赖**: Task 02 (DNS)
- **内存预算**: 1.5G

## 执行内容

1. 执行 `/setup-tempo start` 部署 Tempo 2.7.0
2. 验证服务健康

## Skill 命令

```bash
/setup-tempo start --host 192.168.82.93 --user root --password foxconn.88
/setup-tempo verify --host 192.168.82.93 --user root --password foxconn.88
```

## 端口说明

- `:3200` — HTTP API（Grafana 数据源）
- `:4317` — gRPC（接收 OTel Collector 转发的 Trace）

## 验证标准

- [ ] Tempo 容器运行中
- [ ] `tempo.renew.com:3200/ready` 返回 ready

## 完成记录

- 开始时间:
- 完成时间:
- 备注:
