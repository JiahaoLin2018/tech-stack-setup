# MySQL 8.4 — 部署报告

| 项目 | 值 |
|------|-----|
| 部署日期 | 2026-03-17 |
| 密码更新 | 2026-03-18 |
| 目标机器 | 192.168.82.93 (Server A) |
| 部署目录 | `/opt/tech-stack/mysql/` |
| 容器名称 | tech-mysql / tech-mysqld-exporter |
| 镜像 | mysql:8.4 / prom/mysqld-exporter:v0.16.0 |
| 版本 | MySQL 8.4.8 |

## 端口

| 端口 | 用途 |
|------|------|
| 3306 | MySQL 服务 |
| 9104 | Prometheus 指标 (mysqld-exporter) |

## 账号密码

| 用户 | 密码 | 权限 | 允许来源 |
|------|------|------|---------|
| root | MysRoot_FN7uodzqhy2GXFVj | 全部 | localhost 仅容器内 |
| appuser | MysApp_tGuSCRfjSyyga6ps | readWrite (appdb) | 所有 IP |
| exporter | MysExp_gPG0UvjwxTyOUTpn | PROCESS, REPLICATION CLIENT, SELECT | 所有 IP |

## 连接方式

| 方式 | 地址 |
|------|------|
| JDBC | `jdbc:mysql://mysql.renew.com:3306/appdb` |
| 命令行 | `mysql -h mysql.renew.com -P 3306 -u appuser -p` |
| Python | `pymysql.connect(host='mysql.renew.com', port=3306, user='appuser', password='MysApp_tGuSCRfjSyyga6ps', database='appdb')` |
| Exporter | http://mysql.renew.com:9104/metrics |

## 备注

- mysqld-exporter v0.16.0 使用 `conf/exporter.my.cnf` 配置文件
- exporter 密码需在 `.env` + `conf/exporter.my.cnf` + `init/01_create_app_user.sql` 三处一致
- root 用户已限制为 localhost 登录
