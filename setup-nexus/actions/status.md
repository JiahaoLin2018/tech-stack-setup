# action: status — 查看 Nexus 状态

## 步骤

```bash
SSH_CMD "docker ps --filter name=tech-nexus --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
SSH_CMD "docker stats tech-nexus --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}'"
SSH_CMD "du -sh /opt/tech-stack/nexus/data/ 2>/dev/null"
```

## 输出解读

| Status 字段 | 含义 |
|-------------|------|
| `Up X minutes (healthy)` | 运行正常，API 可访问 |
| `Up X minutes (health: starting)` | 启动中，等待初始化完成 |
| `Up X minutes (unhealthy)` | 运行中但 API 无响应，建议执行 logs |
| 无输出 | 容器未运行，执行 start |

> Nexus 正常运行时内存占用约 1.5-3GB，高于此值请检查 JVM 参数配置。
