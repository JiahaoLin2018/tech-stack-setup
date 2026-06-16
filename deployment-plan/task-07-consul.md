# Task 07 — 部署 Consul

- **状态**: ✅ 完成
- **目标机器**: 192.168.82.93
- **Skill**: setup-consul
- **前置依赖**: Task 02 (DNS)
- **内存预算**: 256M

## 执行内容

1. 执行 `/setup-consul start` 部署 Consul 1.20
2. 验证 UI 和服务注册

## Skill 命令

```bash
/setup-consul start --host 192.168.82.93 --user root --password foxconn.88
/setup-consul verify --host 192.168.82.93 --user root --password foxconn.88
```

## 端口说明

- `:8500` — HTTP API + Web UI
- `:8600` — DNS 接口

## 验证标准

- [ ] Consul 容器运行中
- [ ] Web UI `http://consul-ui.renew.com` 可访问（via infra-nginx）
- [ ] API `consul.renew.com:8500/v1/status/leader` 返回正常

## 完成记录

- 开始时间:
- 完成时间:
- 备注:
