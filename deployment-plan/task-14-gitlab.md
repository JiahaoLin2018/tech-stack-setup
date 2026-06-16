# Task 14 — 部署 GitLab

- **状态**: ✅ 完成
- **目标机器**: 192.168.82.97
- **Skill**: setup-gitlab
- **前置依赖**: Task 01 (Docker on 97), Task 02 (DNS)
- **内存预算**: 4G

## 执行内容

1. 执行 `/setup-gitlab start` 部署 GitLab EE 17.8
2. 等待启动完成（约 3-5 分钟）
3. 执行 `/setup-gitlab activate` 激活许可证
4. 验证访问

## Skill 命令

```bash
/setup-gitlab start --host 192.168.82.97 --user root --password foxconn.88

# 等待启动完成后激活许可证
/setup-gitlab activate --host 192.168.82.97 --user root --password foxconn.88

/setup-gitlab verify --host 192.168.82.97 --user root --password foxconn.88
```

## 端口说明

- `:8929` — HTTP Web UI
- `:8443` — HTTPS
- `:2222` — SSH（Git 操作）

## ⚠️ 内存警告

GitLab 最低需要 4G 内存，97 机器总共 7.6G，运行后剩余 ~3.6G。

## 验证标准

- [x] GitLab 容器运行中
- [x] `http://gitlab.renew.com` Web UI 可访问（via infra-nginx:80）
- [x] 许可证激活：Plan=Ultimate, 有效期至 2055-01-01

## 完成记录

- 完成时间: 2026-03-18 17:05
- 许可证重激活: 2026-03-20 16:39
- 详细信息: `env/gitlab.md`
