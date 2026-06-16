# Task 04 — Nexus OSS 部署

> Maven / NPM 依赖私服 + Docker Registry。对应 architecture-blueprint.md 第五部分阶段一 1-4。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS）已完成 |
| 环境要求 | Docker + Docker Compose 已安装 |
| 跨机部署 | 必须与 infra-nginx 跨主机（`:8082` 端口冲突） |

## 架构约束

- 全局唯一服务（C 类，不接受 `--env`）
- 反代由 task-02 已预配置（`nexus.renew.com` → :8081 + `:8082` TCP 透传）
- 容器宿主机端口：`8081(Web UI / Maven HTTP)` / `8082(Docker Registry)`

## 关键 .env 配置

| 变量 | 说明 |
|------|------|
| `NEXUS_HOSTNAME` | `nexus.renew.com` |
| `NEXUS_PORT` | `8081`（Web UI / Maven HTTP API） |
| `NEXUS_DOCKER_PORT` | `8082`（Docker Registry） |
| `NEXUS_JVM_MIN_HEAP` | `1g` |
| `NEXUS_JVM_MAX_HEAP` | `2g` |
| `NEXUS_DIRECT_MEMORY` | `2g` |

> 首次 admin 密码通过 `docker exec tech-nexus cat /nexus-data/admin.password` 获取，登录后立即修改。

## 部署命令

```bash
/setup-nexus start --host <NEXUS_IP> --user <USER> --password <PASS>
/setup-nexus verify --host <NEXUS_IP> --user <USER> --password <PASS>
```

## 验证标准

- [ ] `http://nexus.renew.com` 可登录
- [ ] 三个默认仓库就绪：`maven-public` / `maven-releases` / `maven-snapshots`
- [ ] Maven Public 代理仓库可拉取依赖（首次登录后手动将 `maven-central` 上游切换为阿里云镜像 `https://maven.aliyun.com/repository/public`）
- [ ] Docker Registry `:8082` 可推送镜像（`docker login nexus.renew.com:8082`，需先在 Web UI 创建 docker-hosted 仓库并启用 HTTP 连接器 :8082）

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 4-6 GB | 2-4 核 | 500 GB+ |

## 并行说明

与 task-03（GitLab）、task-05（Harbor）可全部并行。

## 注意事项

- 首次启动需 1-2 分钟初始化 H2 数据库
- `admin.password` 文件位于容器内 `/nexus-data/admin.password`，首次登录后立即修改
- Maven settings.xml 默认镜像所有请求到 `maven-public`（task-33 GitLab Runner 配置）

## 后续步骤

- Web UI 手动将 `maven-central` proxy 上游切换为阿里云镜像（`https://maven.aliyun.com/repository/public`）
- Web UI 创建 `docker-hosted` 仓库并启用 HTTP 连接器 :8082（Docker Registry 推送入口）
- 创建 CI 用户（用于 task-33 GitLab Runner 推送 SNAPSHOT/RELEASE）
- 密码记录到 `env/nexus.md`
