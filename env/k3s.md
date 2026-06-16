# K3s - 部署报告

| 项目 | 值 |
|------|-----|
| 部署日期 | 2026-04-01 |
| 目标机器 | 192.168.82.93 |
| K3s 版本 | v1.34.5+k3s1 |
| 安装方式 | 二进制安装（系统服务） |
| 二进制路径 | /usr/local/bin/k3s |
| 数据目录 | /var/lib/rancher/k3s/ |
| kubeconfig | /etc/rancher/k3s/k3s.yaml |

## 端口

| 端口 | 用途 |
|------|------|
| 6443 | Kubernetes API Server |
| 10250 | Kubelet |
| 8083 | Traefik HTTP（内部） |
| 8443 | Traefik HTTPS |

## 组件

| 组件 | Namespace | 说明 |
|------|-----------|------|
| CoreDNS | kube-system | DNS 服务，转发 .renew.com 到 dnsmasq |
| Traefik | traefik | Ingress Controller，监听 :8083 |
| local-path-provisioner | kube-system | 本地存储供应 |
| metrics-server | kube-system | 资源指标采集 |
| svclb-traefik | kube-system | Service Load Balancer |

## Token

```
K3S_TOKEN: EnaVwIpMdsNGvfDlzeX2lGBq
```

## 镜像加速配置

```
文件: /etc/rancher/k3s/registries.yaml
源文件: setup-k3s/references/registries.yaml
```

## CoreDNS 转发配置（重要）

> **持久化方式**：K3s 使用 Addon Controller 管理 `coredns` ConfigMap，直接修改会在重启时被重置。必须通过 `coredns-custom` ConfigMap 扩展 DNS 配置。

```
源文件:   setup-k3s/references/coredns-custom.yaml
服务器:   /var/lib/rancher/k3s/server/manifests/coredns-custom.yaml
集群资源: ConfigMap coredns-custom（kube-system）
```

当前配置：将 `.renew.com` 域名转发到 dnsmasq (192.168.82.93:53)，让 K3s Pod 可以解析基础设施域名。

> **为什么放在 `/var/lib/rancher/k3s/server/manifests/`**：这是 K3s 官方自动部署目录，K3s 每次启动自动 apply 该目录下所有 YAML。即使 K3s 重建，配置也会自动恢复，无需手动干预。

```bash
# 查看 coredns-custom 当前配置
kubectl get configmap coredns-custom -n kube-system -o yaml

# 重新应用（如配置丢失）
kubectl apply -f /var/lib/rancher/k3s/server/manifests/coredns-custom.yaml
kubectl rollout restart deployment coredns -n kube-system

# 查看 K3s 管理的 coredns 主配置（不要直接修改）
kubectl get configmap coredns -n kube-system -o yaml
```

## 常用命令

```bash
# 查看节点
kubectl get nodes

# 查看所有 Pod
kubectl get pods -A

# 查看资源使用
kubectl top nodes

# 查看 kubeconfig（用于远程连接）
cat /etc/rancher/k3s/k3s.yaml

# 测试 DNS 解析
kubectl run test-dns --image=busybox --rm -it -- nslookup mysql.renew.com

# 查看 K3s 服务状态
systemctl status k3s

# 重启 K3s
systemctl restart k3s
```

## 远程连接

将 kubeconfig 复制到本地：
```bash
ssh root@192.168.82.93 "cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/config
# 编辑文件，将 server: https://127.0.0.1:6443 改为 server: https://192.168.82.93:6443
```

## 部署说明

### 安装方式

K3s 采用**二进制直接安装**方式，作为 systemd 服务运行，而非 Docker 容器。这是 K3s 的官方推荐部署方式。

**优点**：
- 启动快、资源占用低
- 自动管理 containerd 运行时
- 升级方便（重新运行安装脚本即可）

**与 Docker Compose 服务的关系**：
- K3s 的数据不在 `/opt/tech-stack/` 下
- K3s 使用内置的 containerd，不依赖 Docker
- 其他 Docker Compose 服务通过 DNS 域名与 K3s Pod 通信

### Traefik 端口

单机部署环境下，:80 被 infra-nginx 占用，Traefik 使用 **8083** 端口（Apollo 已迁移至 8601-8605，8080 宿主机空闲）。

流量链路：
```
外部请求 → svclb :8083 → Traefik Service → Traefik Pod :8000 → 业务 Pod
```

### CoreDNS 转发

CoreDNS 已配置将 `.renew.com` 域名转发到 dnsmasq (192.168.82.93:53)，Pod 可以正常解析基础设施域名。

## 备注

- 单节点部署，无高可用
- Traefik 使用 :8083（Apollo 已迁移至 8601-8605，8080 宿主机空闲，但 Traefik 已部署保持 8083）
- CoreDNS 转发 .renew.com → 192.168.82.93 (dnsmasq)
- 镜像加速已配置：/etc/rancher/k3s/registries.yaml
