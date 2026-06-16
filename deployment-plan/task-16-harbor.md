# Task 16 — 部署 Harbor

- **状态**: ✅ 完成
- **目标机器**: 192.168.82.93
- **Skill**: setup-harbor
- **前置依赖**: Task 00 (Docker on 93), Task 02 (DNS)
- **内存预算**: 512M

## 执行内容

1. 执行 `/setup-harbor start` 部署 Harbor 2.12
2. 验证访问

## Skill 命令

```bash
/setup-harbor start --host 192.168.82.93 --user root --password foxconn.88
/setup-harbor verify --host 192.168.82.93 --user root --password foxconn.88
```

## 端口说明

- `:80` — Harbor Web UI + Docker Registry

## 内存规划

部署到 93 机器而非 97 机器，原因：
- 97 机器仅 7.6G 内存，GitLab(4G) + Nexus(2G) 已占用 ~6G
- 93 机器 15G 内存，当前使用 ~4G，剩余 ~11G，空间充裕

## 验证标准

- [x] Harbor 容器运行中
- [x] `harbor.renew.com:80` Web UI 可访问
- [x] `docker login harbor.renew.com` 成功

## 完成记录

- 开始时间: 2026-03-24 14:30
- 完成时间: 2026-03-24 14:47
- 备注: 10 个组件全部 healthy，内存使用 ~120MB，部署报告见 env/harbor.md
