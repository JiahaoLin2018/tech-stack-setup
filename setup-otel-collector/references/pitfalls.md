# 踩坑记录 — setup-otel-collector

> 所有部署中遇到的问题记录于此。问题已在 actions/ 流程中修复，本文件仅作历史存档和排障参考。

## [2026-04-11] OTel Collector 健康检查端口 13133 未映射到宿主机

- **现象**：start.md 和 verify.md 从宿主机执行 `wget http://localhost:13133/health/status` 永远超时
- **根因**：docker-compose.yml 未映射 13133 端口到宿主机，健康检查扩展仅在容器内可达
- **修复**：已将健康等待和验证改为使用已映射的 8888 端口（`curl http://localhost:8888/metrics`）
