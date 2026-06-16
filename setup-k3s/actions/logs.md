# action: logs — 查看 K3s 日志

## 步骤

```bash
# K3s 服务日志（最近 50 行）
SSH_CMD "journalctl -u k3s -n 50 --no-pager"

# 实时日志
SSH_CMD "journalctl -u k3s -f"
```

## 特定组件日志

```bash
# CoreDNS 日志
SSH_CMD "kubectl logs -n kube-system deployment/coredns --tail=50"

# Traefik 日志
SSH_CMD "kubectl logs -n traefik deployment/traefik --tail=50"

# 特定 Pod 日志
SSH_CMD "kubectl logs -n <namespace> <pod-name> --tail=50"
```

## 常用排查命令

```bash
# 查看事件
SSH_CMD "kubectl get events --sort-by='.lastTimestamp' -A | tail -20"

# 查看节点详情
SSH_CMD "kubectl describe node"

# 查看 Pod 详情
SSH_CMD "kubectl describe pod <pod-name> -n <namespace>"
```
