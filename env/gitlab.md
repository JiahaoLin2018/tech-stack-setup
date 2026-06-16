# GitLab EE 部署报告

## 基本信息

| 项目 | 值 |
|------|-----|
| 部署时间 | 2026-03-18 17:05 |
| 目标机器 | 192.168.82.97 (Server B) |
| 版本 | GitLab EE 17.8 |
| 部署目录 | /opt/tech-stack/gitlab |

## 访问信息

| 服务 | 地址 |
|------|------|
| Web UI | http://gitlab.renew.com（via infra-nginx:80 → 97:8929）|
| HTTPS | https://gitlab.renew.com:8443 |
| SSH (Git) | ssh://git@gitlab.renew.com:2222 |

## 账号密码

| 账号 | 密码 |
|------|------|
| root | `Q9jtYby+MWvsX088JYSXQJ+PIt0lhHhh4p85eicEUXM=` |

## 许可证

| 项目 | 值 |
|------|-----|
| 状态 | ✅ 已激活 |
| 计划 | Ultimate |
| 有效期 | 2025-01-01 ~ 2055-01-01 |
| 用户数 | 10000 |

**许可证文件**：`/opt/tech-stack/gitlab/license/`

| 文件 | 用途 |
|------|------|
| `GitLabBV.gitlab-license` | 许可证文件 |
| `license_key` | 私钥（妥善保管） |
| `license_key.pub` | 公钥（volume 挂载到容器） |

## 资源配置

| 配置项 | 值 |
|--------|-----|
| 内存限制 | 4G |
| 内存预留 | 2G |

## 端口映射

| 宿主机端口 | 容器端口 | 用途 |
|-----------|---------|------|
| 8929 | 8929 | HTTP |
| 8443 | 8443 | HTTPS |
| 2222 | 22 | SSH |

## 已知问题

1. **内存紧张**：7.6G 内存 GitLab 占 4G，Rails console 可能 OOM
2. **健康检查**：容器显示 unhealthy，不影响实际使用
3. **gitlab-kas**：间歇性 down，不使用 K8s 可忽略

## 持久化存储

| 目录 | 用途 |
|------|------|
| `./config` | GitLab 配置 |
| `./data` | GitLab 数据（仓库、数据库等） |
| `./logs` | GitLab 日志 |
| `./license` | 许可证公钥（持久化） |

## 运维命令

```bash
# 查看状态
docker exec tech-gitlab gitlab-ctl status

# 查看日志
docker exec tech-gitlab gitlab-ctl tail

# 重启服务
docker exec tech-gitlab gitlab-ctl restart

# 重新配置
docker exec tech-gitlab gitlab-ctl reconfigure

# 备份
docker exec tech-gitlab gitlab-backup create
```

## 部署踩坑记录

1. **端口映射设计**：`external_url` 不含端口 → 内部 nginx 监听 80；docker-compose 端口映射 `8929:80`（宿主机 8929 → 容器 80）；infra-nginx 代理 `gitlab.renew.com:80` → `97:8929`；CI clone URL 为 `http://gitlab.renew.com`（无端口）
2. **镜像加速**：ruby:3.2-slim 需通过已配置的镜像加速器拉取
3. **内存不足**：4G 内存限制下无法运行 `gitlab-rails runner`
   - 解决：手动在 Web UI 上传许可证
