# Task 50 — 上线验证

> 全链路端到端验证（无 skill 调用）。对应 architecture-blueprint.md 第五部分阶段五 5-2。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01~49 全部已完成 |

## 验证清单

### 网络层

- [ ] edge-nginx prod HTTPS 证书有效（`https://*.prod.web.renew.com` 浏览器访问无警告）
- [ ] 公网 DNS 解析正确：`*.prod.{web\|api}.renew.com` → `<EDGE_PROD_PUBLIC_IP>`
- [ ] HTTP 自动 301 → HTTPS
- [ ] 安全头已生效（HSTS / X-Frame-Options 等）

### 应用层

- [ ] 生产 K3s Pod 全部 Running，健康检查通过
- [ ] 业务 API 端到端测试通过（关键路径 / 异常路径）
- [ ] HPA 配置生效（按需扩缩容）
- [ ] PDB 配置就位（高可用滚动更新）
- [ ] Pod 通过 `mysql-prod.renew.com` / `redis-prod.renew.com` 等域名直连生产中间件

### 配置中心

- [ ] Apollo Portal 中 PRO 环境状态可用
- [ ] 生产微服务正确拉取 Apollo 配置（`apollo.meta=http://apollo-config-prod.renew.com`）
- [ ] 配置变更实时生效（修改 → Pod 监听 → 业务热更新）

### 可观测性

- [ ] Grafana 生产看板数据正常（`grafana-prod-ui.renew.com`）
- [ ] 链路追踪数据正常（Tempo prod，TraceQL 按 `resource.deployment.environment="prod"` 过滤）
- [ ] 日志聚合正常（Loki prod，LogQL 按 `deployment_environment="prod"` 过滤）
- [ ] Prometheus 指标采集正常（含 `env=prod` 标签）
- [ ] 告警规则已配置并生效（Alertmanager → 钉钉 / 邮件）
- [ ] Trace ↔ Log ↔ Metrics 三向跳转可用

### 服务治理

- [ ] Consul prod 中可见所有生产微服务，带 `metrics` tag
- [ ] Prometheus consul_sd 已发现生产服务
- [ ] Consul ACL + Gossip 加密已开启

### CI/CD

- [ ] GitLab Runner prod 在线，tag = `prod`
- [ ] Pipeline 触发后由 prod tag Runner 接管
- [ ] 镜像可推送到 Harbor，K3s prod 可拉取
- [ ] `kubectl apply` 滚动更新成功

## 上线发布流程

```
开发侧触发 master 合并 / Release Tag (如 v1.0.0)
     │
     ▼
GitLab CI/CD Pipeline 触发
     │
     ▼
tag: prod Runner 接管
     │
     ├─ 编译构建（Maven/Gradle）
     ├─ 打包镜像 → 推送 Harbor
     ├─ 拉取 Apollo 生产配置
     └─ kubectl apply → 生产 K3s 集群
     │
     ▼
业务 Pod 滚动更新（HPA / PDB 保障可用性）
     │
     ▼
K3s Traefik Ingress 路由生效
     │
     ▼
edge-nginx prod 透传公网流量
     │
     ▼
✅ 生产环境全线贯通，正式对外服务
```

## 灰度策略（推荐）

- 先灰度 1 个 Pod（`replicas: 1`）观察 30 分钟
- 验证业务关键指标 / 链路 / 日志均正常
- 逐步扩容到正常副本数
- 出现告警立即回滚到上一稳定 Tag

## 应急预案

- 回滚命令：`kubectl rollout undo deployment/<name> -n prod`
- 紧急下线：`kubectl scale deployment/<name> --replicas=0 -n prod`
- 配置回滚：Apollo Portal → 历史版本 → 一键回滚
- DNS 切流（最坏情况）：将业务域名切到非生产域名（仅供应急）
