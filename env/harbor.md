# Harbor — 部署报告

| 项目 | 值 |
|------|-----|
| 部署日期 | 2026-03-31（重新部署） |
| 目标机器 | 192.168.82.93 |
| 部署目录 | /opt/tech-stack/harbor/harbor/ |
| 版本 | Harbor v2.12.0 |
| 安装方式 | 官方离线安装器 |

## 端口

| 端口 | 用途 |
|------|------|
| 8880 | HTTP Web UI + Docker Registry |

## 账号密码

| 用户 | 密码 | 权限 | 允许来源 |
|------|------|------|---------|
| admin | `HbrAdm_3l4FYgyvTrysPLKz` | 管理员 | 所有 |
| postgres (DB) | `HbrDb_Internal` | 数据库管理员 | 内部容器 |

## 连接方式

| 方式 | 地址 |
|------|------|
| Web UI | http://harbor.renew.com |
| Docker Login | `docker login harbor.renew.com` |
| Docker Push | `docker tag <image> harbor.renew.com/<project>/<image>` |

## 组件状态

| 组件 | 容器名 | 用途 |
|------|--------|------|
| nginx | nginx | 反向代理 |
| harbor-core | harbor-core | 核心服务 |
| harbor-portal | harbor-portal | Web UI |
| harbor-db | harbor-db | PostgreSQL 数据库 |
| harbor-jobservice | harbor-jobservice | 任务调度 |
| registry | registry | 镜像存储 |
| registryctl | registryctl | Registry 控制 |
| redis | redis | 缓存 |
| trivy-adapter | trivy-adapter | 漏洞扫描 |
| harbor-log | harbor-log | 日志收集 |

## Docker 客户端配置

使用 HTTP 需在客户端 `/etc/docker/daemon.json` 添加：

```json
{
  "insecure-registries": ["harbor.renew.com"]
}
```

> **说明**：统一使用域名（无端口），通过 infra-nginx 代理访问 Harbor，多机部署时无需关心 Harbor 实际部署位置。

修改后重启 Docker：`systemctl restart docker`

**端口说明**：
- Harbor 实际监听 8880 端口（`HARBOR_HTTP_PORT=8880`）
- infra-nginx 将 `harbor.renew.com:80` 代理到 Harbor 8880 端口
- 所有客户端统一通过域名（无端口）访问，走 infra-nginx 代理

## 使用示例

```bash
# 登录
docker login harbor.renew.com
# Username: admin
# Password: HbrAdm_3l4FYgyvTrysPLKz

# 推送镜像
docker tag myapp:v1 harbor.renew.com/library/myapp:v1
docker push harbor.renew.com/library/myapp:v1

# 拉取镜像
docker pull harbor.renew.com/library/myapp:v1
```

## 运维命令

```bash
# 查看状态
cd /opt/tech-stack/harbor/harbor
docker compose ps

# 停止服务
docker compose stop

# 启动服务
docker compose start

# 查看日志
docker compose logs -f harbor-core
```

## 备注

- 部署在 93 机器（内存充裕），而非 97 机器（GitLab + Nexus 已占满）
- 启用 Trivy 漏洞扫描
- 数据目录：`/opt/tech-stack/harbor/data/`（与其他服务统一）
- 配置文件：`/opt/tech-stack/harbor/harbor/harbor.yml`
- **端口从 80 迁移到 8880**，为 infra-nginx 让出 :80

## 部署踩坑记录

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| 远程服务器下载 GitHub 安装包失败 | 国内网络限制 | 本地下载后上传，已优化 skill 自动化此流程 |
| 安装包约 800MB | 离线安装包包含所有镜像 | 已在 skill 中增加本地缓存机制 |
| 数据目录与其他服务不一致 | Harbor 官方默认配置 | 已统一改为 `/opt/tech-stack/harbor/data/` |
| Docker 重启后 Harbor 不自动恢复 | 容器未设置 `restart: unless-stopped` | 执行 `cd /opt/tech-stack/harbor/harbor && docker compose start` |
| 端口迁移后 prepare 报错 KeyError | harbor.yml.example 缺少必需字段 | 已补充 job_loggers、logger_sweeper_duration 等字段 |

> **已优化**：`setup-harbor` skill 已支持自动在本地下载安装包后上传到远程服务器，缓存到 `<skill_dir>/cache/` 目录，避免重复下载。

## Docker 重启后恢复

> **重要**：Harbor 官方安装器生成的容器未设置自动重启策略，`systemctl restart docker` 后需手动恢复。

**恢复命令**：
```bash
cd /opt/tech-stack/harbor/harbor && docker compose start
```

**验证**：
```bash
curl -s -o /dev/null -w '%{http_code}' http://localhost:8880/api/v2.0/ping
# 期望输出：200
```
