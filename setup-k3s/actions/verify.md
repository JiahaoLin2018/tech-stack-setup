# action: verify — 验证 K3s

## 步骤

### 基础验证

```bash
# 节点状态
SSH_CMD "kubectl get nodes"

# 系统 Pod
SSH_CMD "kubectl get pods -n kube-system"

# Traefik
SSH_CMD "kubectl get pods -n traefik"
```

### CoreDNS 转发验证

```bash
# 测试 .renew.com 域名解析（环境级直连域名，nonprod 集群示例）
SSH_CMD "kubectl run test-dns --image=busybox --rm -it --restart=Never -- nslookup mysql-dev.renew.com 2>&1 | tail -5"

# 测试 K8s 内部域名
SSH_CMD "kubectl run test-dns2 --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default.svc.cluster.local 2>&1 | tail -5"
```

### 测试部署验证

```bash
# 创建测试 namespace
SSH_CMD "kubectl create namespace test 2>/dev/null || true"

# 部署 nginx 测试
SSH_CMD "kubectl create deployment nginx-test --image=nginx -n test 2>/dev/null || true"
SSH_CMD "kubectl expose deployment nginx-test --port=80 -n test 2>/dev/null || true"

# 等待就绪
SSH_CMD "kubectl rollout status deployment nginx-test -n test --timeout=60s"

# 验证
SSH_CMD "kubectl get pods -n test"
SSH_CMD "kubectl get svc -n test"

# 清理
SSH_CMD "kubectl delete namespace test"
```

## 预期正常输出示例

```
NAME              STATUS   ROLES                  AGE   VERSION
<K3S_NODE_IP>     Ready    control-plane,master   1d    v1.32.x

Server:    10.43.0.10
Address 1: 10.43.0.10 coredns.kube-system.svc.cluster.local

Name:      mysql-dev.renew.com
Address 1: <Dev MySQL 节点 IP>

NAME                         READY   STATUS    RESTARTS   AGE
nginx-test-xxx-xxx           1/1     Running   0          10s

NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
nginx-test   ClusterIP   10.43.xxx.xxx   <none>        80/TCP    10s
```

## 验证清单

- [ ] 节点状态 Ready
- [ ] CoreDNS Pod Running
- [ ] Traefik Pod Running
- [ ] `mysql-dev.renew.com` 解析正常（nonprod 集群示例）
- [ ] K8s 内部域名解析正常
- [ ] 可创建/删除 Deployment
