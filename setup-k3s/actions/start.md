# action: start — 安装 K3s

## 步骤

### 步骤 0：解析 --env 参数（B 类契约）

```
K3S_ENV = --env 参数值，默认 nonprod
若 K3S_ENV 不是 nonprod 或 prod：
  输出错误："[ERROR] --env 参数无效：'${K3S_ENV}'。允许值：nonprod | prod"
  退出执行
```

- `nonprod`：将创建 Namespace dev / sit / fat / uat
- `prod`：将创建 Namespace prod

### 步骤 1：检查本地 SSH 工具

```bash
# 密码模式
which sshpass > /dev/null 2>&1 || echo "MISSING_SSHPASS"
# 密钥模式
ls ${SSH_KEY_PATH} 2>/dev/null || echo "MISSING_KEY"
```

- 缺少 sshpass（密码模式）→ 提示 `apt install sshpass` 或改用 `--key`
- 密钥文件不存在 → 提示检查路径

### 步骤 2：测试 SSH 连接

```bash
# 密码模式
sshpass -p "${SSH_PASSWORD}" ssh -o StrictHostKeyChecking=no -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} "echo OK"
# 密钥模式
ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} "echo OK"
```

- 连接失败 → 报告错误信息，终止执行

### 步骤 3：检查可用内存

```bash
SSH_CMD "free -m | awk '/^Mem:/{print \$7}'"
```

- 可用内存 < 1024MB → 警告内存不足，询问是否继续

### 步骤 4：检查端口冲突

```bash
# 检查 K3s 核心端口
SSH_CMD "ss -tlnp | grep -E ':6443|:10250|:8472' && echo 'PORT_IN_USE' || echo 'PORT_AVAILABLE'"

# 检查 Traefik 端口（单机部署使用 8083）
SSH_CMD "ss -tlnp | grep ':8083' && echo 'PORT_IN_USE' || echo 'PORT_AVAILABLE'"
```

- 若端口被占用 → 提示用户处理或调整端口规划

### 步骤 5：生成 K3S_TOKEN（如未指定）

```bash
# 若未指定 --token，生成随机 token
SSH_CMD "K3S_TOKEN=\${K3S_TOKEN:-\$(head -c 16 /dev/urandom | base64 | tr -d '/+=' | head -c 24)} && echo \$K3S_TOKEN"
```

### 步骤 6：安装 K3s（国内镜像加速）

```bash
SSH_CMD "curl -sfL https://rancher-mirror.rancher.cn/k3s/k3s-install.sh | \
  INSTALL_K3S_MIRROR=cn \
  K3S_TOKEN=${K3S_TOKEN} \
  sh -s - server \
  --disable traefik \
  --write-kubeconfig-mode 644 \
  --kubelet-arg='max-pods=50'"
```

### 步骤 7：配置镜像加速器和 Harbor 仓库（关键！）

> **踩坑**：
> 1. K3s 安装后系统 Pod 需要从 docker.io 拉取镜像，国内网络无法直接访问，会导致 Pod 一直 ContainerCreating
> 2. Harbor 运行在 HTTP 8880 端口，K3s 默认尝试 HTTPS 443 端口连接，需显式配置

```bash
# 创建配置目录
SSH_CMD "mkdir -p /etc/rancher/k3s"

# 上传 registries.yaml（包含 Docker Hub 加速 + Harbor 配置）
# 必须用 scp/sftp 上传，禁止 SSH heredoc（会导致 ${VAR} 被展开）
scp ${CLAUDE_SKILL_DIR}/references/registries.yaml ${SSH_USER:-root}@${HOST}:/etc/rancher/k3s/registries.yaml

# 重启 K3s 使配置生效
SSH_CMD "systemctl restart k3s"
```

### 步骤 8：等待 K3s 就绪（最多 120 秒）

```bash
SSH_CMD "for i in \$(seq 1 24); do kubectl get nodes > /dev/null 2>&1 && kubectl get nodes && echo READY && break; echo \"等待...\$i/24\"; sleep 5; done"
```

### 步骤 9：验证系统 Pod

```bash
SSH_CMD "kubectl get pods -n kube-system"
```

期望：coredns, local-path-provisioner, metrics-server 全部 Running

> **若 Pod 一直 ContainerCreating**：
> ```bash
> SSH_CMD "kubectl describe pod -n kube-system -l k8s-app=kube-dns | grep -A5 'Events:'"
> ```
> 若显示镜像拉取超时，确认 `/etc/rancher/k3s/registries.yaml` 配置正确并重启 K3s。

### 步骤 10：安装 Traefik Ingress Controller

```bash
# 创建 namespace
SSH_CMD "kubectl create namespace traefik 2>/dev/null || true"

# 上传 traefik-values.yaml
# 注：单机部署使用 8083 端口，已在配置文件中预设
scp ${CLAUDE_SKILL_DIR}/references/traefik-values.yaml ${SSH_USER:-root}@${HOST}:/tmp/

# 应用 HelmChart
SSH_CMD "kubectl apply -f /tmp/traefik-values.yaml"

# 等待 Traefik 就绪
SSH_CMD "kubectl rollout status deployment traefik -n traefik --timeout=120s"
```

> **端口说明**：
> - 单机部署：Traefik 使用 **8083** 端口（:80 被 infra-nginx 占用）
> - 标准部署（6台服务器）：Traefik 使用 8080 端口

### 步骤 11：配置 CoreDNS 转发（持久化方式，使用模板渲染）

> **踩坑**：
> 1. K3s 使用 Addon Controller 管理 CoreDNS ConfigMap
> 2. 直接修改 `coredns` ConfigMap 会被 K3s 重置（重启时触发）
> 3. 正确方式：放入 `/var/lib/rancher/k3s/server/manifests/`，K3s 每次启动自动 apply

```bash
# 读取 .env 中的 DNS_SERVER_IP
DNS_SERVER_IP=$(grep '^DNS_SERVER_IP=' ${CLAUDE_SKILL_DIR}/references/.env 2>/dev/null | cut -d'=' -f2)
if [ -z "${DNS_SERVER_IP}" ]; then
  echo "[ERROR] 未设置 DNS_SERVER_IP，请在 references/.env 中配置"
  exit 1
fi

# 本地渲染模板（envsubst 替换 ${DNS_SERVER_IP}）
DNS_SERVER_IP="${DNS_SERVER_IP}" envsubst '${DNS_SERVER_IP}' < ${CLAUDE_SKILL_DIR}/references/conf/coredns-custom.yaml.tpl > /tmp/coredns-custom.yaml

# 上传到 K3s 自动部署目录（K3s 启动时自动 apply，持久有效）
scp /tmp/coredns-custom.yaml ${SSH_USER:-root}@${HOST}:/var/lib/rancher/k3s/server/manifests/coredns-custom.yaml

# 立即应用（无需等待 K3s 重启）
SSH_CMD "kubectl apply -f /var/lib/rancher/k3s/server/manifests/coredns-custom.yaml"

# 重启 CoreDNS 使配置生效
SSH_CMD "kubectl rollout restart deployment coredns -n kube-system && \
  kubectl rollout status deployment coredns -n kube-system --timeout=60s"
```

**持久化原理**：
- `/var/lib/rancher/k3s/server/manifests/` 是 K3s 官方自动部署目录
- K3s **每次启动自动 apply** 该目录下所有 YAML，无需手动干预

### 步骤 12：按 --env 创建业务 Namespace

```bash
# nonprod 集群：创建 4 个环境 Namespace
if [ "${K3S_ENV}" = "nonprod" ]; then
  for ns in dev sit fat uat; do
    SSH_CMD "kubectl create namespace ${ns} 2>/dev/null && echo 'Created: ${ns}' || echo 'Already exists: ${ns}'"
  done
fi

# prod 集群：创建生产 Namespace
if [ "${K3S_ENV}" = "prod" ]; then
  SSH_CMD "kubectl create namespace prod 2>/dev/null && echo 'Created: prod' || echo 'Already exists: prod'"
fi
```

### 步骤 13：验证 DNS 解析

```bash
# 测试 .renew.com 域名解析
SSH_CMD "kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup mysql-dev.renew.com 2>&1 | tail -8"

# 测试 K8s 内部域名
SSH_CMD "kubectl run test-dns2 --image=busybox:1.36 --rm -it --restart=Never -- nslookup kubernetes.default.svc.cluster.local 2>&1 | tail -5"
```

### 步骤 14：展示连接信息

```
K3s 集群（${K3S_ENV}）已在 ${HOST} 安装完成

节点状态：  kubectl get nodes
系统 Pod：  kubectl get pods -n kube-system
Traefik：   kubectl get pods -n traefik
Namespace： kubectl get namespaces

端口信息:
  K3s API:   6443
  Traefik:   8083 (单机部署)

kubeconfig:
  服务器路径: /etc/rancher/k3s/k3s.yaml
  复制到本地: ssh root@${HOST} "cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/config

验证 DNS 解析:
  kubectl run test-dns --image=busybox --rm -it -- nslookup mysql-dev.renew.com
```

---

## 部署报告输出

> 部署完成后，必须在项目 `env/` 目录下生成或更新该服务的部署报告文件 `env/k3s.md`。

报告模板：

```markdown
# K3s — 部署报告

| 项目 | 值 |
|------|-----|
| 部署日期 | YYYY-MM-DD |
| 集群环境 | nonprod / prod |
| 目标机器 | <IP> |
| K3s 版本 | v1.34.x |
| 安装方式 | 二进制安装（systemd 系统服务） |
| 二进制路径 | /usr/local/bin/k3s |
| 数据目录 | /var/lib/rancher/k3s/ |
| 配置目录 | /etc/rancher/k3s/ |
| kubeconfig | /etc/rancher/k3s/k3s.yaml |
| 镜像加速配置 | /etc/rancher/k3s/registries.yaml |

## Namespace

| 集群 | Namespace |
|------|-----------|
| nonprod | dev, sit, fat, uat |
| prod | prod |

## 认证信息

K3S_TOKEN: <token>

> kubeconfig 内含集群证书，请妥善保管，不要提交到 git。

## 端口

| 端口 | 用途 |
|------|------|
| 6443 | Kubernetes API Server |
| 10250 | Kubelet |
| 8083 | Traefik HTTP（单机部署） |
| 8443 | Traefik HTTPS |
```

报告文件路径：`<project_root>/env/k3s.md`

---

## 故障排查

### Pod 一直 ContainerCreating

```bash
SSH_CMD "kubectl describe pod -n kube-system <pod-name> | grep -A5 'Events:'"
```

通常原因：镜像拉取超时，确认 registries.yaml 配置并重启 K3s。

### CoreDNS 无法解析 .renew.com

```bash
SSH_CMD "kubectl get configmap coredns-custom -n kube-system -o yaml"
SSH_CMD "kubectl logs -n kube-system deployment/coredns --tail=20"
```

确认 DNS_SERVER_IP 正确，重启 CoreDNS：
```bash
SSH_CMD "kubectl rollout restart deployment coredns -n kube-system"
```
