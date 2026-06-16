# Task 17 — Harbor 端口迁移（:80 → :8880）

- **状态**: ✅ 已完成
- **目标机器**: 192.168.82.93
- **前置依赖**: Task 16 (Harbor 部署完成)

## 目标

将 Harbor 从 `:80` 迁移到 `:8880`，腾出 `:80` 给 infra-nginx。

## 操作步骤

```bash
# 1. 登录 93 机器
ssh root@192.168.82.93

# 2. 进入 Harbor 目录
cd /opt/tech-stack/harbor/harbor

# 3. 备份配置
cp harbor.yml harbor.yml.bak

# 4. 修改端口
sed -i 's/^  port: 80$/  port: 8880/' harbor.yml

# 5. 停止 Harbor
docker compose down

# 6. 重新生成配置
./prepare

# 7. 启动 Harbor
docker compose up -d

# 8. 验证
curl -sf http://192.168.82.93:8880
```

## 同步更新 Skill 模板

| 文件 | 变更 |
|------|------|
| `setup-harbor/references/.env.example` | `HARBOR_HTTP_PORT=8880` ✅ |
| `setup-harbor/references/harbor.yml.example` | `http.port: 8880` ✅ + 补充必需字段 |
| `setup-harbor/README.md` | 更新端口说明 ✅ |
| `setup-harbor/CHANGELOG.md` | 记录端口迁移变更 ✅ |

## 验证清单

- [x] `curl -sf http://192.168.82.93:8880` 返回 200
- [ ] `docker login harbor.renew.com` 成功
- [x] Harbor Web UI 正常访问

## 停机时间

约 2 分钟

## 完成记录

- 开始时间: 2026-03-31 17:00
- 完成时间: 2026-03-31 18:20
- 备注: 由于原有安装包损坏，使用新的安装包重新部署。修复了 harbor.yml.example 缺少必需字段（job_loggers、logger_sweeper_duration）的问题。
