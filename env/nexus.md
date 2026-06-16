# Nexus — 部署报告

| 项目 | 值 |
|------|-----|
| 部署日期 | 2026-03-20 |
| 目标机器 | 192.168.82.97 |
| 部署目录 | /opt/tech-stack/nexus/ |
| 容器名称 | tech-nexus |
| 镜像 | sonatype/nexus3:3.87.0 |
| 版本 | 3.87.0 OSS |

## 端口

| 端口 | 用途 |
|------|------|
| 8081 | Web UI + Maven 仓库 |
| 8082 | Docker 仓库（预留） |

## 账号密码

| 用户 | 密码 | 权限 | 允许来源 |
|------|------|------|---------|
| admin | 6198dd8f-67d1-4479-8b8f-0c1f0b6ac6c4 | 管理员 | 所有 |

> 首次登录后需修改密码

## 连接方式

| 方式 | 地址 |
|------|------|
| Web UI | http://nexus.renew.com（通过 infra-nginx 代理） |
| Maven Mirror | http://nexus.renew.com/repository/maven-public/ |
| Docker Registry | nexus.renew.com:8082（需先配置） |

## JVM 配置

| 参数 | 值 | 说明 |
|------|-----|------|
| Xms | 512m | 最小堆内存 |
| Xmx | 1g | 最大堆内存 |
| MaxDirectMemorySize | 1g | 直接内存 |
| 容器限制 | 2g | Docker 内存限制 |

## 资源使用

| 指标 | 值 |
|------|-----|
| 内存使用 | ~1GB / 2GB |
| CPU | 低负载 |

## 备注

- 97 机器内存紧张（总共 7.6G，GitLab 占 4G），Nexus 已缩减 JVM 配置
- data 目录权限已设置为 uid=200（nexus 用户）
- 首次启动较慢（约 60 秒），健康检查通过后可正常使用
