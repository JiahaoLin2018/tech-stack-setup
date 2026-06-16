# Task 08 — 部署 Apollo

- **状态**: ✅ 完成
- **目标机器**: 192.168.82.93
- **Skill**: setup-apollo
- **前置依赖**: Task 02 (DNS)
- **内存预算**: 512M

## 执行内容

1. 执行 `/setup-apollo start` 部署 Apollo 2.5.0（含独立 MySQL）
2. 验证管理界面

## Skill 命令

```bash
/setup-apollo start --host 192.168.82.93 --user root --password foxconn.88
/setup-apollo verify --host 192.168.82.93 --user root --password foxconn.88
```

## 端口说明（独立部署模式）

- `:8070` — Apollo Portal（管理界面，通过 infra-nginx 代理 apollo.renew.com）
- `:8601` — DEV Config Service
- `:8602` — SIT Config Service
- `:8603` — FAT Config Service
- `:8604` — UAT Config Service
- `:8605` — PRO Config Service
- `:8611~8615` — Admin Service（各环境，仅 Portal 内部使用）
- `:3307` — Apollo 独立 MySQL

## 注意事项

- Apollo 自带独立 MySQL 实例，与业务 MySQL (Task 03) 互不影响
- Spring Boot 业务服务按部署环境选择对应 Config Service 域名：`apollo-config-dev.renew.com` / `apollo-config-fat.renew.com` / `apollo-config-prod.renew.com` 等（通过 infra-nginx 代理）

## 验证标准

- [ ] Apollo 全部 12 个容器运行中（DB+5Config+5Admin+Portal）
- [ ] Portal `apollo.renew.com:8070` 可访问
- [ ] Config DEV 健康检查通过（`curl apollo-config-dev.renew.com/health`）

## 完成记录

- 开始时间:
- 完成时间:
- 备注:
