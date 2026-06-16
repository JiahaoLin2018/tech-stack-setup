# Task 15 — 部署 Nexus

- **状态**: ✅ 完成
- **目标机器**: 192.168.82.97
- **Skill**: setup-nexus
- **前置依赖**: Task 01 (Docker on 97), Task 02 (DNS)
- **内存预算**: 2G（缩减，文档建议 4-6G）

## 执行内容

1. 执行 `/setup-nexus start` 部署 Nexus 3.87 OSS
2. 修改 JVM heap 为 1G（默认可能是 2G+）
3. 验证访问

## Skill 命令

```bash
/setup-nexus start --host 192.168.82.97 --user root --password foxconn.88
/setup-nexus verify --host 192.168.82.97 --user root --password foxconn.88
```

## 端口说明

- `:8081` — Nexus Web UI + Maven 仓库
- `:8082` — Docker 仓库（如配置）

## 内存调优

- JVM heap: `-Xms512m -Xmx1024m`（默认值可能更大，需修改 `.env` 或 JVM 参数）
- 97 机器内存紧张，Nexus 必须限制 JVM heap

## 验证标准

- [x] Nexus 容器运行中
- [x] `nexus.renew.com` Web UI 可访问（通过 infra-nginx:80 代理）
- [x] Maven 仓库可正常访问

## 完成记录

- 开始时间: 2026-03-20 11:30
- 完成时间: 2026-03-20 11:42
- 备注:
  - JVM 参数已缩减：Xms512m, Xmx1g, DirectMemory=1g
  - 容器内存限制 2g
  - data 目录权限已修复 (uid=200)
  - 初始密码：6198dd8f-67d1-4479-8b8f-0c1f0b6ac6c4
  - 内存使用约 1GB / 2GB
