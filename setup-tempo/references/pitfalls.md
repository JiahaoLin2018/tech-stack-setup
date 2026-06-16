# 踩坑记录 — setup-tempo

> 所有部署中遇到的问题记录于此。问题已在 actions/ 流程中修复，本文件仅作历史存档和排障参考。

## [2026-04-11] Tempo OTLP 端口未暴露导致 OTel Collector 无法转发 traces

- **现象**：OTel Collector 日志报 `connection refused` 连接 `tempo-{nonprod|prod}.renew.com:4317`
- **根因**：docker-compose.yml 中 OTLP 4317/4318 端口被注释掉，未映射到宿主机，OTel Collector 通过域名无法到达
- **修复**：取消注释 OTLP 端口映射，宿主机端口改为 14317/14318 避免与同机 OTel Collector 的 4317/4318 冲突；同步更新 OTel Collector 配置指向 `tempo-{nonprod|prod}.renew.com:14317`
