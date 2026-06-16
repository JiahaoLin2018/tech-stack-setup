# setup-k3s

K3s 轻量级 Kubernetes 集群的完整生命周期管理，支持非生产和生产双集群模式。

## 简介

K3s 是轻量级 Kubernetes 发行版，本项目用于运行业务应用层（前端、Gateway、Spring Boot 微服务），基础设施层（MySQL、Redis、Consul 等）保持 Docker Compose 部署。

**架构定位**：
```
┌─────────────────────────────────────────┐
│  K3s 集群（业务应用层）                  │
│  前端 | Gateway | Spring Boot 微服务     │
└─────────────────────────────────────────┘
                    │
                    │ *.renew.com 域名连接
                    ▼
┌─────────────────────────────────────────┐
│  Docker Compose（基础设施层）            │
│  MySQL | Redis | Consul | Apollo | ...  │
└─────────────────────────────────────────┘
```

## 双集群模式

| 集群类型 | `--env` 值 | Namespace | 部署位置 |
|---------|-----------|-----------|---------|
| 非生产集群 | `nonprod` | dev / sit / fat / uat | 非生产物理机 |
| 生产集群 | `prod` | prod | 独立物理机 / 隔离 VPC |

## 业务 Pod 接入边界

setup-k3s 仅提供业务运行底座，业务 Pod 接入可观测性 / Apollo / 中间件由其他 skill 处理：

| 关注点 | 由谁处理 |
|--------|---------|
| OTel 资源属性（`deployment.environment={env}`）注入 | setup-gitlab-runner 的 `app.sh` |
| OTLP endpoint 注入（`otel-{nonprod\|prod}.renew.com:4317`） | 同上 |
| Consul `metrics` tag 注册 | 业务 `application.yml` |
| Apollo Meta 注入（`apollo-config-{env}.renew.com`） | `app.sh` |
| `*.renew.com` 域名解析（业务 Pod 直连基础设施） | 本 skill 的 CoreDNS 转发配置 |

## 前置依赖

- **setup-dns** 已部署，DNS 服务正常运行
- **hosts.lan** 中已配置 K3s 节点域名

## 安装

```bash
# 安装 skill
claude-code skill install setup-k3s

# 部署非生产集群（默认）
/setup-k3s start --host <K3S_NODE_IP>

# 部署生产集群
/setup-k3s start --env prod --host <K3S_PROD_NODE_IP>
```

## 用法

```
/setup-k3s [action] [选项]

action: start（默认）| stop | status | verify | logs

选项:
  --env <env>        集群环境（nonprod|prod，默认: nonprod）
  --host <ip>        部署目标 IP（默认: localhost）
  --user <user>      SSH 用户名（默认: root）
  --password <pass>  SSH 密码（与 --key 二选一）
  --key <path>       SSH 私钥路径（与 --password 二选一）
  --ssh-port <n>     SSH 端口（默认: 22）
  --token <token>    K3s 集群 token（默认: 自动生成）
```

## Actions 说明

| Action | 说明 |
|--------|------|
| `start` | 安装 K3s 集群，按 `--env` 创建对应 Namespace |
| `stop` | 卸载 K3s 集群 |
| `status` | 查看 K3s 集群运行状态 |
| `verify` | 验证 K3s 集群和 CoreDNS 转发 |
| `logs` | 查看 K3s 服务日志 |

## 配置说明

K3s 与其他服务的部署方式不同：

| 对比项 | 基础设施服务 | K3s |
|--------|------------|-----|
| 部署方式 | Docker Compose | 二进制 + systemd |
| 数据目录 | `/opt/tech-stack/<service>/data/` | `/var/lib/rancher/k3s/` |
| 配置目录 | `/opt/tech-stack/<service>/conf/` | `/etc/rancher/k3s/` |
| 服务管理 | `docker compose up/down` | `systemctl start/stop k3s` |

### 关键配置文件

| 文件 | 说明 |
|------|------|
| `/etc/rancher/k3s/k3s.yaml` | kubeconfig |
| `/etc/rancher/k3s/registries.yaml` | 镜像加速配置 |
| `/root/.k3s_token` | Token 备份 |

### 环境变量

参考 `references/.env.example`：

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `DNS_SERVER_IP` | DNS 服务器 IP（CoreDNS 转发目标） | 必填 |

## 端口规划

| 端口 | 用途 | 说明 |
|------|------|------|
| 6443 | K3s API | kubectl 连接端口 |
| 8083 | Traefik Ingress | 单机部署专用（:80 被 infra-nginx 占用） |
| 10250 | Kubelet | K8s 内部通信 |

## CoreDNS 转发

K3s Pod 需要访问基础设施域名（如 `mysql-{env}.renew.com`），CoreDNS 配置将 `.renew.com` 转发到 dnsmasq。

**注意事项**：
- K3s 使用 Addon Controller 管理 CoreDNS ConfigMap
- 直接修改 `coredns` ConfigMap 会被重置
- 正确方式：创建 `coredns-custom` ConfigMap

## 镜像加速

国内网络无法直接访问 Docker Hub，必须配置镜像加速器：

```yaml
# /etc/rancher/k3s/registries.yaml
mirrors:
  docker.io:
    endpoint:
      - "https://docker.1ms.run"
  harbor.renew.com:
    endpoint:
      - "http://harbor.renew.com"
```

## 故障排查

| 症状 | 可能原因 | 解决方案 |
|------|---------|---------|
| Pod ContainerCreating | 镜像拉取失败 | 检查 registries.yaml |
| ImagePullBackOff harbor.renew.com | Harbor 配置缺失 | 添加 harbor.renew.com mirror |
| Pod 无法解析 *.renew.com | CoreDNS 转发丢失 | 检查 coredns-custom ConfigMap |

## 资源预算

| 组件 | 内存 |
|------|------|
| K3s Server | ~512MB |
| CoreDNS | ~50MB |
| Traefik | ~100MB |
| **合计** | **~650MB** |

## 相关文档

- `SKILL.md` — 技术执行指令
- `references/pitfalls.md` — 踩坑记录
- `references/coredns-config.example` — CoreDNS 转发配置示例
