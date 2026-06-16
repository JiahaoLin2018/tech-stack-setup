# Task 27 — K3s 非生产集群部署

> 部署非生产业务应用运行底座。对应 architecture-blueprint.md 第五部分阶段三 3-6。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS）已完成；推荐先完成 task-05（Harbor）以拉取业务镜像 |
| 环境要求 | 干净物理机/虚拟机，本机 DNS 指向 `<DNS_IP>` |
| 端口 | :6443（API Server）/ :8083（Traefik Ingress）/ :10250（Kubelet） |

## 架构约束

- B 类域级共用，仅作为业务应用运行底座（前端 / Gateway / 微服务）
- 所有中间件 / LGT 栈 / Apollo / Runner 均在 K3s **外部**
- 通过 K8s Namespace（dev/sit/fat/uat）实现 4 环境逻辑隔离
- CoreDNS 必须用 `coredns-custom` ConfigMap 配置 `.renew.com` 转发到 dnsmasq（直接改 `coredns` ConfigMap 会被 Addon Controller 重置）
- Traefik 单机部署用 :8083（容器内 8000，避免非 root 端口绑定问题）

## 关键配置

| 变量 | 说明 |
|------|------|
| `K3S_ENV` | `nonprod` |
| `DNS_SERVER_IP` | dnsmasq 节点 IP（CoreDNS 转发目标，铁律二允许的 IP 例外）|
| Namespace | `dev` / `sit` / `fat` / `uat`（自动创建） |
| containerd 镜像加速 | `/etc/rancher/k3s/registries.yaml`：`docker.io` → 国内加速；`harbor.renew.com` → `http://harbor.renew.com`（默认 HTTPS 443 不通） |

## 部署命令

```bash
/setup-k3s start --host <K3S_NONPROD_IP> --env nonprod --user <USER> --password <PASS>
/setup-k3s verify --host <K3S_NONPROD_IP> --env nonprod --user <USER> --password <PASS>
```

## 验证标准

- [ ] `kubectl get nodes` 返回节点 Ready
- [ ] `kubectl get ns` 显示 dev / sit / fat / uat 均存在
- [ ] 系统 Pod 全部 Running（含 CoreDNS / Traefik / metrics-server）
- [ ] Traefik 监听 :8083：`curl -I http://<K3S_NONPROD_IP>:8083`
- [ ] Pod 内可解析 `.renew.com`：`kubectl run test --image=busybox --rm -it -- nslookup mysql-dev.renew.com`
- [ ] containerd 可拉取 Harbor 镜像

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 2-8 GB | 2-4 核 | 100 GB |

> 起步 2 vCPU / 2G / 50G，按业务 Pod 规模扩容（多节点扩容时复用 `K3S_TOKEN`）。

## 并行说明

- 与 task-28（Tempo nonprod）/ task-29（Loki nonprod）可并行（无依赖）
- 与 task-07~26 中间件可并行（不同机器）

## 注意事项

- K3s 内置 containerd（不依赖 Docker），`/etc/rancher/k3s/registries.yaml` 必须配 `harbor.renew.com` HTTP（默认 HTTPS 443 不通）
- kubeconfig（`/etc/rancher/k3s/k3s.yaml`）含集群证书，妥善保管，禁止入 git
- 业务 Pod 的 OTel 注入 / Apollo Meta / Consul 注册由 task-33 的 `app.sh` 处理，本 task 不涉及
- K3s 二进制（kubectl）是 symlink，CI 容器中需用静态 kubectl-bin（task-33 处理）

## 后续步骤

- kubeconfig 备份至 `env/k3s-nonprod.kubeconfig`（task-33 需要）
- task-33（Runner nonprod）依赖本 task
- task-35（edge-nginx nonprod）proxy_pass 后端为 `k3s-nonprod.renew.com:8083`
