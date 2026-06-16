# 踩坑记录 — setup-grafana

> 所有部署中遇到的问题记录于此。问题已在 actions/ 流程中修复，本文件仅作历史存档和排障参考。

## 1. datasources.yml 缺少关键字段 [v1.0.0 已修复]

**现象**：Grafana 数据源配置不完整，跨数据源引用失败。

**根因**：datasources.yml 缺少关键字段。

**修复**：
- 添加 `uid` 字段（prometheus/tempo/loki），确保跨数据源引用正确
- 添加 `orgId: 1`，显式声明组织 ID
- 添加 `editable: false`，防止通过 UI 误修改 provisioning 配置
- Tempo: 添加 `spanStartTimeShift: '-1h'` 和 `spanEndTimeShift: '1h'`，扩大 Trace → Logs 跳转的时间范围
- Tempo: 添加 `search.hide: false`，确保 TraceQL 搜索功能可用
- Loki: 添加 `maxLines: 1000`，设置日志预览行数
- Prometheus: 添加 `httpMethod: POST`，优化查询性能

---

## 2. envsubst 全量替换吞掉 `${__value.raw}` 致 Log↔Trace 跳转失效

**现象**：Grafana 中点击日志的 traceId 跳转到 Tempo，URL 变成空字符串，Log → Trace 跳转完全不工作。

**根因**：`datasources.yml.tpl` 中 derivedFields 含 `'$${__value.raw}'`（双 $ 是 Grafana provisioning 转义，期望渲染后保留为 `${__value.raw}` 由 Grafana 运行时解析）。但 `envsubst` 默认全量替换所有 `${VAR}` 占位符，看到 `${__value.raw}` 时尝试用环境变量替换，环境中无此变量则替换为空字符串。

**修复**：`start.md` 步骤 5 的 envsubst 改用变量白名单形式，仅替换显式列出的变量；同时注意 `\$` 转义防止控制端 shell 提前展开（envsubst 命令在 ssh `"..."` 双引号内）：

```bash
envsubst '\${PROMETHEUS_HOST} \${PROMETHEUS_PORT} \${TEMPO_HOST} \${TEMPO_PORT} \${LOKI_HOST} \${LOKI_PORT}' < tpl > out
```
