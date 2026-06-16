# Task 47 — Apollo 生产全量部署（合并 3 容器）

> 一次到位部署生产 Apollo 全套。对应 architecture-blueprint.md 第五部分阶段四 4-6。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-06（非生产 Apollo Portal 已就绪，用于跨网段挂载） |
| 环境要求 | 生产网段独立服务器；本机内存预留 ≥ 6 GB |
| 反代规则 | infra-nginx 已预配置 `apollo-config-prod.renew.com` 跨网段反代 |

## 架构约束

- D 类合并部署，`--env prod` 一次拉起 **3 个容器**：
  1. Apollo 内置 MySQL × 1（独立物理实例，与 nonprod MySQL 完全隔离）
  2. Apollo Config Service × 1（:8605）
  3. Apollo Admin Service × 1（:8615）
- Schema：`ApolloConfigDB_prod`（仅一个）
- Apollo 内置环境名：`PRO`（Apollo 硬编码大写）
- 容器后缀：`prod`

## 容器清单

| 容器 | 端口 | Schema |
|------|------|--------|
| `tech-apollo-db` | :3307 | ApolloConfigDB_prod |
| `tech-apollo-config-prod` | :8605 | ApolloConfigDB_prod |
| `tech-apollo-admin-prod` | :8615 | ApolloConfigDB_prod |

## 关键 .env 配置

| 变量 | 说明 |
|------|------|
| `APOLLO_DB_ROOT_PASSWORD` | 生产 Apollo 内置 MySQL root 密码（与 nonprod 完全独立） |
| `APOLLO_DB_PORT` | `3307` |
| `APOLLO_CONFIG_PORT_PROD` | `8605` |
| `APOLLO_ADMIN_PORT_PROD` | `8615` |
| `APOLLO_NAMESPACE_LOCK_SWITCH` | 生产建议 `true` |

> prod 模式不使用 `APOLLO_PORTAL_PORT` / `APOLLO_ENVS` / `APOLLO_PORTAL_ENVS` / `APOLLO_PRO_META`（这些仅 nonprod 模式生效）。

## 部署命令

```bash
/setup-apollo start --host <APOLLO_PROD_IP> --env prod --user <USER> --password <PASS>
/setup-apollo verify --host <APOLLO_PROD_IP> --env prod --user <USER> --password <PASS>
```

## 跨网段挂载（部署完成后）

在非生产 Portal 中配置 `PRO` 环境 Meta Server 路由（确保 task-02 infra-nginx `21-apollo-config.conf` 中 `APOLLO_PROD_HOST` 已填正确）：

```json
{
  "PRO": "http://apollo-config-prod.renew.com"
}
```

> Apollo 2.5.0 硬编码：Portal 配置 JSON key 必须用大写 `PRO`，容器/DB 后缀用小写 `prod`。

## 验证标准

- [ ] 3 个容器全部 Running
- [ ] `curl http://apollo-config-prod.renew.com/health` 返回 UP（infra-nginx 跨网段反代）
- [ ] 在 nonprod Portal 中 PRO 环境状态变为 **可用**
- [ ] PRO 环境可读写配置，与 nonprod 数据完全隔离

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 4-6 GB | 2 核+ | 50 GB |

## 并行说明

- 与 task-36~40（生产中间件）可并行（无依赖）
- 与 task-41~46（生产 K3s/LGT）可并行
- **关键**：Apollo prod 自带 MySQL，不依赖 task-36（业务 MySQL）

## 注意事项

- Apollo MySQL 物理隔离要求严格（生产专属独立实例）
- 跨网段挂载是单向：Portal（非生产）→ Config（生产），后端数据不互通
- 生产 Apollo 修改配置变更影响实时生效，操作需谨慎

## 后续步骤

- 生产 Spring Boot 微服务的 `apollo.meta=http://apollo-config-prod.renew.com`（task-48 app.sh 自动注入）
- 生产 Portal 访问认证（强烈建议开启）
