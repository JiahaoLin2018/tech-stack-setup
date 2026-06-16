datacenter = "dc1"
data_dir = "/consul/data"
log_level = "${CONSUL_LOG_LEVEL}"

# Server 角色（单节点 bootstrap 模式）
server = true
bootstrap_expect = 1
client_addr = "0.0.0.0"
bind_addr = "0.0.0.0"

# UI 控制台
ui_config {
  enabled = true
}

# ============================================================
# Gossip 加密（内网部署默认禁用）
# ============================================================
# 启用步骤：
#   1. 在部署机器执行下面命令生成 32 字节 base64 密钥：
#        docker run --rm hashicorp/consul:1.20 consul keygen
#      输出示例：kY8zN2mP9xQ1wE5rT7vB3cF6hJ4kL0sA==
#   2. 取消下面 encrypt 一行注释，把上面命令的输出填入引号：
# encrypt = "REPLACE_WITH_CONSUL_KEYGEN_OUTPUT"

# ============================================================
# ACL 访问控制（内网部署默认禁用）
# ============================================================
# 启用步骤：
#   1. 取消下面整段 acl {} 块的注释
#   2. tokens.initial_management 改为合法 UUID（生成命令）：
#        cat /proc/sys/kernel/random/uuid
#   3. 启动后用该 UUID 作为 bootstrap token 调用：
#        consul acl bootstrap
# acl {
#   enabled = true
#   default_policy = "deny"
#   enable_token_persistence = true
#   tokens {
#     initial_management = "REPLACE_WITH_UUID"
#   }
# }

# 性能调优
performance {
  raft_multiplier = 1
}

# Prometheus 指标导出（被 setup-prometheus consul_sd 抓取）
telemetry {
  prometheus_retention_time = "60s"
  disable_hostname = true
}
