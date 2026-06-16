# 部署报告目录

每个服务部署完成后自动生成报告，记录账号、密码、连接方式等信息。

> **此目录包含敏感信息（密码），不应提交到 git。**

## 密码生成规则

```
格式：{服务缩写}{角色}_{16位随机大小写字母+数字}
长度：24-28 位
示例：MysRoot_FN7uodzqhy2GXFVj
```

| 服务缩写 | 服务 | 角色缩写 | 含义 |
|---------|------|---------|------|
| Dns | dnsmasq | Adm | 管理员 |
| Mys | MySQL | Root/App/Exp | 根用户/应用/Exporter |
| Rds | Redis | Default/Exp | 默认用户/Exporter |
| Mgo | MongoDB | Root/App/Exp | 根用户/应用/Exporter |
| Rmq | RabbitMQ | Adm | 管理员 |
| Apo | Apollo | Db | 数据库 |
| Grf | Grafana | Adm | 管理员 |
| Hbr | Harbor | Adm/Db | 管理员/数据库 |

部署时按此规则随机生成密码，生成后记录在对应服务的 `env/<service>.md` 报告中。不做集中存储，各报告文件即为唯一密码记录。

## 已部署服务

| 服务 | 报告文件 | 机器 | 状态 |
|------|---------|------|------|
| DNS (dnsmasq) | [dns.md](dns.md) | 192.168.82.93 | ✅ |
| MySQL 8.4 | [mysql.md](mysql.md) | 192.168.82.93 | ✅ |
| Redis 8.0 | [redis.md](redis.md) | 192.168.82.93 | ✅ |
| MongoDB 8.0 | [mongodb.md](mongodb.md) | 192.168.82.93 | ✅ |
| RabbitMQ 4.0 | [rabbitmq.md](rabbitmq.md) | 192.168.82.93 | ✅ |
| Consul 1.20 | [consul.md](consul.md) | 192.168.82.93 | ✅ |
| Apollo 2.5.0 | [apollo.md](apollo.md) | 192.168.82.93 | ✅ |
| Tempo 2.7.0 | [tempo.md](tempo.md) | 192.168.82.93 | ✅ |
| Loki 3.5.0 | [loki.md](loki.md) | 192.168.82.93 | ✅ |
| Prometheus v3.2 | [prometheus.md](prometheus.md) | 192.168.82.93 | ✅ |
| Grafana 11.4 | [grafana.md](grafana.md) | 192.168.82.93 | ✅ |
| OTel Collector | [otel-collector.md](otel-collector.md) | 192.168.82.93 | ✅ |
| GitLab EE 17.8 | gitlab.md | 192.168.82.97 | ✅ |
| Nexus 3.87 | [nexus.md](nexus.md) | 192.168.82.97 | ✅ |
| Harbor 2.12 | harbor.md | 192.168.82.93 | ✅ |
