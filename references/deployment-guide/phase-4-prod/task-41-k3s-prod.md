# Task 41 — K3s 生产集群部署

> 部署生产业务应用运行底座（物理孤岛）。对应 architecture-blueprint.md 第五部分阶段四 4-8。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS）+ task-05（Harbor）已完成 |
| 环境要求 | 全新物理机或隔离 VPC（与非生产无任何互通路径） |
| 端口 | :6443 / :8083 / :10250 |

## 架构约束

- B 类，生产物理孤岛独立 1 套
- 仅运行生产微服务，所有中间件 / LGT 栈 / Apollo 在 K3s 外部
- 通过 K8s Namespace `prod` 单一隔离
- CoreDNS 必须用 `coredns-custom` ConfigMap 配置 `.renew.com` 转发到全局唯一的 dnsmasq（DNS 是全局共享层，不分域）
- containerd 必须配置 `harbor.renew.com` HTTP 镜像源（`/etc/rancher/k3s/registries.yaml`）

## 关键配置

| 变量 | 值 |
|------|---|
| `K3S_ENV` | `prod` |
| `DNS_SERVER_IP` | dnsmasq 节点 IP |
| Namespace | `prod`（自动创建） |
| 部署位置 | 完全独立物理机或隔离 VPC |

## 部署命令

```bash
/setup-k3s start --host <K3S_PROD_IP> --env prod --user <USER> --password <PASS>
/setup-k3s verify --host <K3S_PROD_IP> --env prod --user <USER> --password <PASS>
```

## 验证标准

- [ ] `kubectl get nodes` 返回节点 Ready
- [ ] `kubectl get ns` 显示 `prod`
- [ ] 系统 Pod 全部 Running
- [ ] Traefik 监听 :8083
- [ ] Pod 内可解析 `mysql-prod.renew.com`
- [ ] 与非生产网络物理隔离（防火墙规则验证）

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 8 GB+ | 4 核+ | 200 GB |

> 起步 4 vCPU / 8G / 100G，业务规模扩展后引入多节点。

## 并行说明

- 与 task-36~40（生产中间件）可并行
- 与 task-42/43（Tempo/Loki prod）可并行

## 注意事项

- 物理孤岛要求：与非生产 K3s 集群无任何网络互通（防火墙隔离）
- kubeconfig（`/etc/rancher/k3s/k3s.yaml`）含集群证书，备份至 `env/k3s-prod.kubeconfig`（task-48 需要），禁止入 git
- K3s 内置 containerd（不依赖 Docker），镜像源在 `/etc/rancher/k3s/registries.yaml` 配置 `harbor.renew.com` HTTP（无需 Docker daemon.json）
- 业务 Pod 的 OTel 注入 / Apollo Meta / Consul 注册由 task-48 的 `app.sh` 处理，本 task 不涉及

## 后续步骤

- task-48（Runner prod）依赖本 task
- task-49（edge-nginx prod）proxy_pass 后端为 `k3s-prod.renew.com:8083`
