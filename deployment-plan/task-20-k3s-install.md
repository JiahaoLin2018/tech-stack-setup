# Task 20 — K3s 安装与 CoreDNS 转发配置

- **状态**: ✅ 完成
- **目标机器**: 192.168.82.93
- **Skill**: setup-k3s
- **前置依赖**: Task 19 (DNS 配置更新完成)

## 目标

在 93 机器上安装 K3s 单节点集群，并配置 CoreDNS 转发 `.renew.com` 域名到 dnsmasq。

## 执行命令

```bash
/setup-k3s install --host 192.168.82.93 --user root --password foxconn.88
/setup-k3s verify --host 192.168.82.93 --user root --password foxconn.88
```

## 安装内容

| 组件 | 版本 | 用途 |
|------|------|------|
| K3s | v1.34.5+k3s1 | 轻量级 Kubernetes |
| Traefik | v3.6.12 | Ingress Controller（:8083） |
| CoreDNS | - | 集群内 DNS，转发 .renew.com 到 dnsmasq |

## 端口规划

| 端口 | 用途 | 说明 |
|------|------|------|
| 6443 | Kubernetes API | K3s 核心 |
| 10250 | Kubelet | K3s 核心 |
| **8083** | Traefik HTTP | 单机部署（:80 被 infra-nginx 占用） |
| 8443 | Traefik HTTPS | 单机部署 |

## 资源预算

| 组件 | 内存 |
|------|------|
| K3s Server | ~512MB |
| CoreDNS | ~50MB |
| Traefik | ~100MB |
| **合计** | **~650MB** |

## 验证清单

- [x] `kubectl get nodes` → STATUS=Ready
- [x] `kubectl get pods -n kube-system` → 全部 Running
- [x] `kubectl get pods -n traefik` → Traefik Pod Running
- [x] Pod 内 `nslookup mysql.renew.com` → 返回正确 IP
- [x] Pod 内 `nslookup kubernetes.default.svc.cluster.local` → 正常

## 完成记录

- 开始时间: 2026-04-01 15:48
- 完成时间: 2026-04-01 16:23
- K3s 版本: v1.34.5+k3s1
- 部署报告: env/k3s.md

## 踩坑记录

详见 `setup-k3s/CHANGELOG.md`：

1. **镜像拉取超时** → 配置 `/etc/rancher/k3s/registries.yaml` 镜像加速
2. **Traefik 端口冲突** → 单机部署使用 8083 端口（已在 deployment-topology.md 规划）
3. **Traefik 权限错误** → 容器内端口改为 8000（非 root 可绑定）
4. **hostPort 冲突** → 移除 hostPort，让 svclb 处理流量转发
