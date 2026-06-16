# Task 06 — Apollo 非生产全量部署（合并 10 容器）

> 一次到位部署非生产 Apollo 全套。对应 architecture-blueprint.md 第五部分阶段二 2-1。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-01（DNS）+ task-02（infra-nginx）已完成 |
| 环境要求 | Docker + Docker Compose 已安装；本机内存预留 ≥ 12 GB |
| 反代规则 | infra-nginx 已预配置 `apollo.renew.com` 与 `apollo-config-{dev,sit,fat,uat}.renew.com` |

## 架构约束

- D 类合并部署，`--env nonprod` 一次拉起 **10 个容器**：
  1. Apollo 内置 MySQL × 1（Schema：`ApolloPortalDB` + `ApolloConfigDB_{dev,sit,fat,uat}`）
  2. Apollo Portal × 1（:8070）
  3. Apollo Config Service × 4（dev:8601 / sit:8602 / fat:8603 / uat:8604）
  4. Apollo Admin Service × 4（dev:8611 / sit:8612 / fat:8613 / uat:8614）
- Apollo 内置 MySQL 与业务 MySQL（task-07 等）**完全独立**
- Apollo 2.5.0 硬编码：FWS→FAT 映射，Portal 中 PRO 的 JSON key 大写、容器/DB 后缀小写

## 容器清单

| 容器 | 端口 | Schema |
|------|------|--------|
| `tech-apollo-db` | :3307 | ApolloPortalDB + ApolloConfigDB_dev/sit/fat/uat |
| `tech-apollo-portal` | :8070 | ApolloPortalDB |
| `tech-apollo-config-dev` | :8601 | ApolloConfigDB_dev |
| `tech-apollo-config-sit` | :8602 | ApolloConfigDB_sit |
| `tech-apollo-config-fat` | :8603 | ApolloConfigDB_fat |
| `tech-apollo-config-uat` | :8604 | ApolloConfigDB_uat |
| `tech-apollo-admin-dev` | :8611 | ApolloConfigDB_dev |
| `tech-apollo-admin-sit` | :8612 | ApolloConfigDB_sit |
| `tech-apollo-admin-fat` | :8613 | ApolloConfigDB_fat |
| `tech-apollo-admin-uat` | :8614 | ApolloConfigDB_uat |

## 关键 .env 配置

| 变量 | 说明 |
|------|------|
| `APOLLO_DB_ROOT_PASSWORD` | Apollo 内置 MySQL root 密码（按 `ApoDb_{16位随机}` 规则）|
| `APOLLO_DB_PORT` | `3307`（与业务 MySQL :3306 错开） |
| `APOLLO_PORTAL_PORT` | `8070` |
| `APOLLO_CONFIG_PORT_DEV/SIT/FAT/UAT` | `8601` / `8602` / `8603` / `8604` |
| `APOLLO_ADMIN_PORT_DEV/SIT/FAT/UAT` | `8611` / `8612` / `8613` / `8614` |
| `APOLLO_ENVS` | `dev,sit,fat,uat,pro`（Apollo 内置环境名，PRO 在 task-47 接入后可用）|
| `APOLLO_PRO_META` | `http://apollo-config-prod.renew.com`（task-47 部署后生效）|
| `APOLLO_CONSUMER_TOKEN_SALT` | 至少 32 字符的安全盐值，生产建议替换 |
| `APOLLO_NAMESPACE_LOCK_SWITCH` | 生产建议 `true`（防止多人同时修改冲突） |

> Portal 默认账号 apollo / admin 不在 .env 中，首次登录后立即修改。

## 部署命令

```bash
/setup-apollo start --host <APOLLO_IP> --env nonprod --user <USER> --password <PASS>
/setup-apollo verify --host <APOLLO_IP> --env nonprod --user <USER> --password <PASS>
```

## 验证标准

- [ ] 10 个容器全部 Running，healthcheck 通过
- [ ] `http://apollo.renew.com` Portal 可登录（默认 apollo / 自定义密码）
- [ ] Portal 环境列表显示 DEV/SIT/FAT/UAT 状态均为 **可用**（PRO 暂不可用，task-47 后生效）
- [ ] `curl http://apollo-config-dev.renew.com/health` 返回正常（其余 sit/fat/uat 同理）
- [ ] Apollo 内置 MySQL 中 5 个 Schema 全部已创建

## 资源建议

| 内存 | CPU | 磁盘 |
|------|-----|------|
| 10-12 GB | 4 核+ | 100 GB |

> 资源拆分：1 MySQL（≈2g）+ 1 Portal（≈1g）+ 4 Config × 1g + 4 Admin × 1g。

## 注意事项

- DB 初始化必须用 `docker cp` + `exec`（禁止 `exec -i` stdin 重定向，会丢字符）
- Portal 配置修改后必须重启 Portal 容器才生效
- 跨网段访问生产配置：Portal 通过 `apollo-config-prod.renew.com`（infra-nginx 反代）跨网段读写生产 Config Service
- 容器内部通信用 Compose 服务名（`apollo-config-dev:8080` 等），合规非 IP 硬编码

## 后续步骤

- 创建项目（AppId）和 namespace（task-34 demo 需要 `tech.common` 公共 namespace）
- 修改默认 apollo / admin 密码
- 任意时机可继续 task-07 起的非生产中间件部署（无依赖关系）
