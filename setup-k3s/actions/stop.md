# action: stop — 卸载 K3s

## ⚠️ 警告

卸载将删除：
- 所有 Pod 和容器
- 所有配置和密钥
- 所有数据卷（local-path）

**请在卸载前备份重要数据！**

## 步骤

### 步骤 1：确认卸载

询问用户确认是否继续卸载。

### 步骤 2：停止 K3s 服务

```bash
SSH_CMD "systemctl stop k3s"
```

### 步骤 3：执行卸载脚本

```bash
SSH_CMD "/usr/local/bin/k3s-uninstall.sh"
```

### 步骤 4：验证卸载

```bash
SSH_CMD "systemctl status k3s 2>&1 | head -3 || echo 'K3s 服务已移除'"
SSH_CMD "ls /var/lib/rancher/k3s 2>/dev/null || echo '数据目录已清理'"
```

### 步骤 5：清理残留（可选）

```bash
# 清理网络接口
SSH_CMD "ip link show cni0 2>/dev/null && ip link delete cni0 || echo 'cni0 已清理'"
SSH_CMD "ip link show flannel.1 2>/dev/null && ip link delete flannel.1 || echo 'flannel.1 已清理'"

# 清理数据目录（谨慎）
SSH_CMD "rm -rf /var/lib/rancher /etc/rancher /var/lib/kubelet /run/k3s"
```

## 预期正常输出示例

```
K3s 服务已移除
数据目录已清理
cni0 已清理
flannel.1 已清理
```
