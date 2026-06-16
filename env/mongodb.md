# MongoDB 8.0 — 部署报告

| 项目 | 值 |
|------|-----|
| 部署日期 | 2026-03-17 |
| 密码更新 | 2026-03-18 |
| 目标机器 | 192.168.82.93 (Server A) |
| 部署目录 | `/opt/tech-stack/mongodb/` |
| 容器名称 | tech-mongodb / tech-mongodb-exporter |
| 镜像 | mongo:8.0 / percona/mongodb_exporter:0.43.1 |
| 版本 | MongoDB 8.0.19 |

## 端口

| 端口 | 用途 |
|------|------|
| 27017 | MongoDB 服务 |
| 9216 | Prometheus 指标 (mongodb-exporter) |

## 账号密码

| 用户 | 密码 | 权限 | 数据库 |
|------|------|------|--------|
| admin | MgoRoot_Msf4AozEQTM8P52Q | root (全部) | admin |
| appuser | MgoApp_H8hX6sFfQnLsNWy8 | readWrite + dbAdmin | appdb |
| exporter | MgoExp_lULS0hxZXtRUOB1s | clusterMonitor + read(local) | admin |

## 连接方式

| 方式 | 地址 |
|------|------|
| MongoDB URI (appuser) | `mongodb://appuser:{password}@mongodb.renew.com:27017/appdb?authSource=appdb` |
| mongosh | `mongosh mongodb.renew.com:27017/appdb -u appuser -p` |
| Spring Boot | `spring.data.mongodb.uri=mongodb://appuser:{password}@mongodb.renew.com:27017/appdb?authSource=appdb` |
| Exporter | http://mongodb.renew.com:9216/metrics |

## 配置

| 参数 | 值 |
|------|-----|
| WiredTiger cache | 1 GB |
| maxConns | 500 |
| slowOpThreshold | 200ms |

## 备注

- MongoDB 8.0 已移除 `storage.journal.enabled` 配置项
- exporter 使用专用 `exporter` 用户（最小权限）
