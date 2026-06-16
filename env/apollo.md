# Apollo 2.5.0 — 部署报告

| 项目 | 值 |
|------|-----|
| 部署日期 | 2026-04-07 |
| 目标机器 | 192.168.82.93 (Server A) |
| 部署目录 | `/opt/tech-stack/apollo/` |
| 部署模式 | 独立部署（5 环境 × 独立 Config/Admin） |
| 容器数量 | 12（1 DB + 5 Config + 5 Admin + 1 Portal） |
| 镜像 | mysql:8.4 / apolloconfig/*:2.5.0 |

## 端口总览

| 环境（Apollo 内部名） | 容器后缀 | Config 端口 | Admin 端口 |
|----------------------|---------|------------|-----------|
| DEV | dev | 8601 | 8611 |
| SIT | sit | 8602 | 8612 |
| FAT | fat | 8603 | 8613 |
| UAT | uat | 8604 | 8614 |
| **PRO** | **prod** | 8605 | 8615 |
| Portal | — | 8070 | — |
| MySQL | — | 3307 | — |

## 数据库分配

| 环境 | Schema |
|------|--------|
| DEV | ApolloConfigDB_dev |
| SIT | ApolloConfigDB_sit |
| FAT | ApolloConfigDB_fat |
| UAT | ApolloConfigDB_uat |
| PRO | ApolloConfigDB_prod |
| Portal | ApolloPortalDB |

## 账号密码

| 用途 | 用户 | 密码 |
|------|------|------|
| Apollo Portal 登录 | apollo | admin（首次登录后修改） |
| Apollo 独立 MySQL | root | ApoDb_ooO11ZdC7BNYcHIL |

## 连接方式

| 方式 | 地址 |
|------|------|
| Portal UI | http://apollo.renew.com（通过 infra-nginx 代理） |
| DEV Config | http://apollo-config-dev.renew.com（通过 infra-nginx 代理） |
| SIT Config | http://apollo-config-sit.renew.com |
| FAT Config | http://apollo-config-fat.renew.com |
| UAT Config | http://apollo-config-uat.renew.com |
| PROD Config | http://apollo-config-prod.renew.com |
| 独立 MySQL | `mysql -h apollo.renew.com -P 3307 -u root -p`（泛解析到 Apollo 所在机器） |

## Spring Boot 接入

| 环境 | apollo.meta |
|------|-------------|
| dev | http://apollo-config-dev.renew.com |
| sit | http://apollo-config-sit.renew.com |
| fat | http://apollo-config-fat.renew.com |
| uat | http://apollo-config-uat.renew.com |
| prod | http://apollo-config-prod.renew.com |

> CI/CD 部署时 app.sh 自动注入 `-Dapollo.meta=http://apollo-config-${env}.renew.com`，无需手动配置。

```yaml
# application.yml 示例（本地开发默认 fat 环境）
apollo:
  meta: http://apollo-config-fat.renew.com
  bootstrap:
    enabled: true
app:
  id: ${spring.application.name}
```

## PortalDB 配置（ApolloPortalDB.ServerConfig）

| 配置项 | 值 | 说明 |
|--------|-----|------|
| apollo.portal.envs | dev,sit,fat,uat,pro | 环境列表（Apollo 内部：DEV/SIT/FAT/UAT/PRO） |
| apollo.portal.meta.servers | {"DEV":"http://apollo-config-dev:8080",...,"PRO":"http://apollo-config-prod:8080"} | 各环境 Meta 地址 |
| organizations | [{"orgId":"TECH","orgName":"技术部"},...] | 组织结构 |
| consumer.token.salt | Ap0ll0_T0k3n_S4lt_2026_R3n3w_C0m#X9zKmPqVw | Token 盐值（安全必须） |
| configView.memberOnly.envs | dev,sit,fat,uat,pro | 权限隔离环境 |

> **注意**：Apollo 内置环境名 `PRO`（生产），容器和数据库使用 `prod` 后缀。Portal 配置中 JSON key 为 `PRO`，容器名为 `apollo-config-prod`。

## ConfigDB 配置（各环境独立）

| 环境 | eureka.service.url | namespace.lock.switch |
|------|-------------------|-----------------------|
| dev | http://apollo-config-dev:8080/eureka/ | true |
| sit | http://apollo-config-sit:8080/eureka/ | true |
| fat | http://apollo-config-fat:8080/eureka/ | true |
| uat | http://apollo-config-uat:8080/eureka/ | true |
| prod | http://apollo-config-prod:8080/eureka/ | true |

## 备注

- 独立部署模式：每个环境拥有独立的 Config Service + Admin Service + DB Schema
- **环境命名规则**：Apollo 内置环境名 `PRO`（生产），容器和数据库使用 `prod` 后缀
- Apollo 官方镜像不会自动创建数据库，首次部署由 start.md 自动执行 SQL 初始化
- Portal 通过 Docker 内网容器名连接各环境 Config Service（`http://apollo-config-{后缀}:8080`）
- Spring Boot 客户端通过 infra-nginx 代理访问（`apollo-config-{后缀}.renew.com`）
- Portal 默认账号 apollo/admin，首次登录后务必修改密码
- **2026-04-13 迁移**：数据库命名规范化，`ApolloConfigDB` → `ApolloConfigDB_dev`，`ApolloConfigDB_pro` → `ApolloConfigDB_prod`；容器名 `apollo-config-pro` → `apollo-config-prod`；Portal 配置使用 `PRO` 环境名
- FWS 不可用（Apollo 2.5.0 硬编码映射 FWS→FAT），改用 SIT 替代
