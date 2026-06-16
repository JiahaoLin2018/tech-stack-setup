# action: status — 查看 K3s 状态

## 步骤

```bash
# K3s 服务状态
SSH_CMD "systemctl status k3s --no-pager | head -10"

# 节点状态
SSH_CMD "kubectl get nodes -o wide"

# 系统 Pod
SSH_CMD "kubectl get pods -n kube-system"

# Traefik Pod
SSH_CMD "kubectl get pods -n traefik"

# 资源使用
SSH_CMD "kubectl top nodes 2>/dev/null || echo 'metrics-server 未就绪'"
```

## 预期正常输出示例

```
● k3s.service - Lightweight Kubernetes
   Loaded: loaded (/etc/systemd/system/k3s.service; enabled)
   Active: active (running) since Mon 2026-03-31 10:00:00 CST

NAME              STATUS   ROLES                  AGE   VERSION
<K3S_NODE_IP>     Ready    control-plane,master   1d    v1.32.x

NAMESPACE     NAME                                      READY   STATUS
kube-system   coredns-xxx-xxx                           1/1     Running
kube-system   local-path-provisioner-xxx-xxx            1/1     Running
kube-system   metrics-server-xxx-xxx                    1/1     Running

NAMESPACE     NAME                                      READY   STATUS
traefik       traefik-xxx-xxx                           1/1     Running

NAME              CPU(cores)   MEMORY(bytes)
<K3S_NODE_IP>     200m         800Mi
```
