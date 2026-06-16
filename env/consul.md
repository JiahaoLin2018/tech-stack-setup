# Consul 1.20 — 部署报告


| 项目   | 值                         |
| ---- | ------------------------- |
| 部署日期 | 2026-03-18                |
| 目标机器 | 192.168.82.93 (Server A)  |
| 部署目录 | `/opt/tech-stack/consul/` |
| 容器名称 | tech-consul               |
| 镜像   | hashicorp/consul:1.20     |
| 版本   | Consul 1.20.6             |


## 端口


| 端口   | 用途                |
| ---- | ----------------- |
| 8500 | HTTP API + Web UI |
| 8600 | DNS 接口 (UDP)      |


## 密钥


| 项目          | 值                                            |
| ----------- | -------------------------------------------- |
| Gossip 加密密钥 | llJUnhpe7aanP2INecoO+WeJGJcOXG66yJLTkGE0LJc= |


> 无用户名密码（ACL 未启用），通过 Gossip 加密保障集群通信安全。

## 连接方式


| 方式           | 地址                                                                          |
| ------------ | --------------------------------------------------------------------------- |
| Web UI       | [http://consul-ui.renew.com](http://consul-ui.renew.com)（via infra-nginx）/ 直连 `http://consul.renew.com:8500` |
| HTTP API     | `curl http://consul.renew.com:8500/v1/status/leader`                        |
| Spring Cloud | `spring.cloud.consul.host=consul.renew.com` `spring.cloud.consul.port=8500` |
| 服务注册         | `spring.cloud.consul.discovery.service-name=${spring.application.name}`     |


## 配置


| 参数              | 值                        |
| --------------- | ------------------------ |
| datacenter      | dc1                      |
| server mode     | bootstrap-expect=1 (单节点) |
| raft_multiplier | 1                        |
| gossip 加密       | 已启用                      |
| ACL             | 未启用（开发环境）                |


## 备注

- Gossip 加密密钥通过 `consul keygen` 生成，注入到 `conf/consul.hcl` 的 `encrypt` 字段
- Prometheus 通过 consul_sd 自动发现已注册的微服务
- 生产环境建议启用 ACL（`conf/consul.hcl` 中取消 acl 注释块）

