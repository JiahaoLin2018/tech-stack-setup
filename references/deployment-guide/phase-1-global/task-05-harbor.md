# Task 05 — Harbor 部署

> Docker 镜像仓库 + Trivy 漏洞扫描。对应 architecture-blueprint.md 第五部分阶段一 1-5。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS）已完成 |
| 环境要求 | Docker + Docker Compose 已安装；磁盘 ≥ 500 GB |
| Harbor 安装包 | 官方安装器 v2.12.0（`./install.sh --with-trivy`） |

## 架构约束

- 全局唯一服务（C 类，不接受 `--env`）
- 反代由 task-02 已预配置（`harbor.renew.com` → :8880）
- HTTP 模式（无 SSL），所有 Docker 客户端必须配置 `insecure-registries`
- 容器宿主机端口：`8880(HTTP)`（让出 :80 给 infra-nginx）

## 关键 .env 配置

| 变量 | 说明 |
|------|------|
| `HARBOR_HOSTNAME` | `harbor.renew.com` |
| `HARBOR_HTTP_PORT` | `8880`（让出 :80 给 infra-nginx） |
| `HARBOR_HTTPS_PORT` | `443`（HTTP 模式可不用） |
| `HARBOR_ADMIN_PASSWORD` | admin 初始密码（按 `HbrAdm_{16位随机}` 规则） |
| `HARBOR_DB_PASSWORD` | 内置 PostgreSQL 密码（按 `HbrDb_{16位随机}` 规则） |
| `HARBOR_DATA_DIR` | `/opt/tech-stack/harbor/data` |
| `HARBOR_VERSION` | `v2.12.0` |

## 部署命令

```bash
/setup-harbor start --host <HARBOR_IP> --user <USER> --password <PASS>
/setup-harbor verify --host <HARBOR_IP> --user <USER> --password <PASS>
```

## 验证标准

- [ ] `http://harbor.renew.com` 可登录
- [ ] `docker login harbor.renew.com -u admin` 成功
- [ ] Trivy 漏洞扫描组件已就绪（Admin → Interrogation Services）
- [ ] `library` 默认项目可推送测试镜像

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 2-4 GB | 1-2 核 | 500 GB+ |

## 并行说明

与 task-03（GitLab）、task-04（Nexus）可全部并行。

## 注意事项

- HTTP 模式下，每个 Docker 客户端 / K3s 节点必须配置 `insecure-registries: ["harbor.renew.com"]`：
  - Docker daemon：`/etc/docker/daemon.json`
  - K3s containerd：`/etc/rancher/k3s/registries.yaml`（task-27 / task-41 处理）
- Harbor 由官方安装器管理，容器名前缀 `harbor-*`（与项目 `tech-*` 命名约定不同，属于例外）
- 初始密码记录到 `env/harbor.md`

## 后续步骤

- 创建 Robot Account（task-33 / 48 推荐使用 Robot 替代 admin 密码）
- 创建项目（如 `library` / `business` / `infra`）
- task-27（K3s nonprod）/ task-41（K3s prod）的 `registries.yaml` 必须包含 `harbor.renew.com`
