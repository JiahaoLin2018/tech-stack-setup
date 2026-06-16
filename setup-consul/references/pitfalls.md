# 踩坑记录 — setup-consul

> 所有部署中遇到的问题记录于此。问题已在 actions/ 流程中修复，本文件仅作历史存档和排障参考。

## 1. 生产环境 ACL 启用指南

> **重要**：Consul ACL 启用是运维决策，涉及 Token 管理和策略设计。通过 `.env` 配置启用。

### 1.1 为什么不默认启用 ACL

1. **Token 管理复杂**：启用 ACL 后需为每个服务生成并分发 Token
2. **策略设计**：需定义哪些服务可以注册、发现、写入
3. **安全风险**：错误配置可能导致服务无法注册或发现
4. **回滚成本**：ACL 启用后禁用需清理 Token 持久化数据

### 1.2 启用步骤

**步骤 1：修改 .env**

```bash
# 在部署目录修改 .env
vim /opt/tech-stack/consul-prod/.env

# 设置 ACL 配置（多行需用换行符）
CONSUL_ACL_CONFIG="acl = {
  enabled = true
  default_policy = \"deny\"
  enable_token_persistence = true
}"
```

**步骤 2：重新渲染配置并重启**

```bash
cd /opt/tech-stack/consul-prod
set -a && source .env && set +a
envsubst < conf/consul.hcl.tpl > conf/consul.hcl
docker restart tech-consul-prod
```

**步骤 3：生成 Management Token**

```bash
# 进入容器
docker exec -it tech-consul-prod sh

# 生成 management token（首次启用时自动创建）
consul acl bootstrap
# 输出示例：
# Accessor ID:   xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# Secret ID:     yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy  ← 这是 Token，务必保存
# Description:   Bootstrap Token (Global Management)
# Policies:      00000000-0000-0000-0000-000000000001
```

**步骤 4：为微服务创建 Token**

```bash
# 创建策略（允许服务注册和发现）
consul acl policy create -name "service-register" -rules 'service_prefix "" { policy = "write" }' -token <management-token>

# 创建 Token 关联策略
consul acl token create -description "Spring Boot Service Token" -policy-name "service-register" -token <management-token>
# 输出 Secret ID 即为微服务使用的 Token
```

**步骤 5：Spring Boot 配置 Token**

```yaml
spring:
  cloud:
    consul:
      host: consul-prod.renew.com
      port: 8500
      discovery:
        service-name: ${spring.application.name}
        acl-token: <service-token>  # 步骤 4 生成的 Token
      config:
        acl-token: <service-token>
```

### 1.3 验证 ACL 启用

```bash
# 无 Token 访问应返回 403
curl http://consul-prod.renew.com:8500/v1/agent/members

# 有 Token 访问应返回正常
curl -H "X-Consul-Token: <management-token>" http://consul-prod.renew.com:8500/v1/agent/members
```

### 1.4 回滚方案

如需禁用 ACL：

```bash
# 1. 修改 .env，清空 ACL 配置
vim /opt/tech-stack/consul-prod/.env
# CONSUL_ACL_CONFIG=# ACL 未启用

# 2. 重新渲染配置
cd /opt/tech-stack/consul-prod
set -a && source .env && set +a
envsubst < conf/consul.hcl.tpl > conf/consul.hcl

# 3. 删除持久化数据中的 ACL 状态
docker exec tech-consul-prod rm -rf /consul/data/acl*

# 4. 重启容器
docker restart tech-consul-prod
```

---

## 2. Gossip 加密密钥轮换

> 如 Gossip 密钥泄露，需执行轮换。

### 2.1 生成新密钥

```bash
docker exec tech-consul-{env} consul keygen
# 输出示例：kY8zN2mP9xQ1wE5rT7vB3cF6hJ4kL0sA==
```

### 2.2 更新 .env

```bash
# 在部署目录修改 .env
CONSUL_ENCRYPT_KEY=kY8zN2mP9xQ1wE5rT7vB3cF6hJ4kL0sA==
```

### 2.3 重新注入并重启

```bash
# 重新执行 start action 会自动注入新密钥
/setup-consul start --env prod --host <ip>
```

---

## 3. 多环境部署注意事项

### 3.1 容器名和目录隔离

每个环境使用独立容器名和目录：

| 环境 | 容器名 | 部署目录 |
|------|--------|----------|
| dev | tech-consul-dev | /opt/tech-stack/consul-dev/ |
| sit | tech-consul-sit | /opt/tech-stack/consul-sit/ |
| fat | tech-consul-fat | /opt/tech-stack/consul-fat/ |
| uat | tech-consul-uat | /opt/tech-stack/consul-uat/ |
| prod | tech-consul-prod | /opt/tech-stack/consul-prod/ |

### 3.2 域名解析

- 直连域名 `consul-{env}.renew.com` 必须写入 `setup-dns/references/hosts.lan`
- Web UI 域名 `consul-{env}-ui.renew.com` 由 infra-nginx 代理，无需写入 hosts.lan
- 访问直连域名时**必须带端口**：`consul-dev.renew.com:8500`

---

## 4. 与 Prometheus consul_sd 的协作约束

> Prometheus（`setup-prometheus`）通过 `consul_sd_configs` 把 Consul 当作 Spring Boot 微服务的发现源。这层契约一旦失配，Prometheus 抓不到任何业务指标，且现象隐蔽（Targets 页面为空，无报错）。

### 4.1 metrics tag 是强制前置条件

Prometheus 的 `spring-boot-{env}` job 配置了 `tags: ['metrics']` 过滤：

```yaml
# setup-prometheus/.../prometheus.nonprod.yml
- job_name: 'spring-boot-dev'
  consul_sd_configs:
    - server: 'consul-dev.renew.com:8500'
      tags: ['metrics']        # ← 仅发现带此 tag 的服务
```

业务 Spring Boot 注册到 Consul 时若未在 `spring.cloud.consul.discovery.tags` 中包含 `metrics`，对应 Pod **永远不会出现在 Prometheus Targets 列表**。

排查方法：

```bash
# 1. 查看 Consul 中已注册服务的 tag 列表
curl http://consul-dev.renew.com:8500/v1/catalog/service/<service-name> | jq '.[].ServiceTags'

# 2. 期望输出包含 "metrics"，否则在业务 application.yml 补：
#    spring.cloud.consul.discovery.tags: metrics
```

### 4.2 prod 启用 ACL 后 Prometheus 需配置 Token

`prod` 环境开启 ACL 后，Prometheus 通过 `consul_sd_configs` 读取服务列表的请求会被 Consul 拒绝，Targets 页面同样为空。

修复路径（在 `setup-prometheus` 的 `prometheus.prod.yml` 中追加 token）：

```yaml
- job_name: 'spring-boot'
  consul_sd_configs:
    - server: 'consul-prod.renew.com:8500'
      tags: ['metrics']
      token: '${CONSUL_ACL_TOKEN}'   # 由 Consul ACL 生成的只读 Token
```

Token 生成（在 Consul prod 容器内执行）：

```bash
# 创建只读策略（仅允许读 service catalog）
docker exec tech-consul-prod consul acl policy create \
  -name "prometheus-readonly" \
  -rules 'service_prefix "" { policy = "read" } node_prefix "" { policy = "read" }' \
  -token <management-token>

# 创建 Token
docker exec tech-consul-prod consul acl token create \
  -description "Prometheus consul_sd" \
  -policy-name "prometheus-readonly" \
  -token <management-token>
# Secret ID 即为 CONSUL_ACL_TOKEN
```

### 4.3 业务 Spring Boot 在 prod 下的 ACL Token

启用 ACL 后，业务服务注册到 Consul 也需要 Token（参见本文件 §1.2 步骤 4-5）。Token 可放入 Apollo 配置中心 `application` namespace 的 `spring.cloud.consul.discovery.acl-token`，避免硬编码到 application.yml。

---

## 5. Consul 自身指标抓取（可选）

Consul 1.20 在 `/v1/agent/metrics?format=prometheus` 暴露自身运行指标（Raft、Gossip、RPC 延迟等）。当前 `setup-prometheus` 默认**未抓取此端点**，仅把 Consul 用作服务发现源。

如需把 Consul 自身指标纳入监控，可在 `prometheus.{nonprod|prod}.yml` 追加 static_configs：

```yaml
- job_name: 'consul-dev'
  metrics_path: '/v1/agent/metrics'
  params:
    format: ['prometheus']
  static_configs:
    - targets: ['consul-dev.renew.com:8500']
  relabel_configs:
    - target_label: env
      replacement: dev
```

> 启用 ACL 后同样需要 Token（见 §4.2）。
