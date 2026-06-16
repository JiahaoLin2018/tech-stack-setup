# CoreDNS Custom ConfigMap - 持久化的 DNS 转发配置
#
# 重要说明：
# - K3s 使用 Addon Controller 管理 CoreDNS ConfigMap，直接修改会被重置
# - K3s 默认 CoreDNS 配置包含 `import /etc/coredns/custom/*.override`
# - 通过创建 coredns-custom ConfigMap，可以实现持久化的自定义 DNS 配置
#
# 使用方法（由 actions/start.md 自动执行）：
#   DNS_SERVER_IP=<dnsmasq IP> envsubst < coredns-custom.yaml.tpl > coredns-custom.yaml
#   kubectl apply -f coredns-custom.yaml
#   kubectl rollout restart deployment coredns -n kube-system
#
# ${DNS_SERVER_IP} 为 dnsmasq 服务器 IP，来自 references/.env 中的 DNS_SERVER_IP 配置
# 注：CoreDNS 转发目标使用 IP 是铁律二的合理例外（转发目标本身就是 DNS 服务器）
#
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  renew.override: |
    # 转发 .renew.com 到 dnsmasq（${DNS_SERVER_IP}）
    forward renew.com ${DNS_SERVER_IP} {
        policy sequential
        health_check 10s
    }
