# Action: status

查看 dnsmasq DNS 服务运行状态（支持本地和远程两种部署模式）。

## 命令格式

```
/setup-dns status [--host <ip>] [--user <user>] [--password <pass>|--key <path>]
```

## 步骤

1. **查看容器状态**：
   ```bash
   ssh ... "docker inspect tech-dns --format='状态: {{.State.Status}}  健康: {{.State.Health.Status}}' 2>/dev/null || echo '容器未运行'"
   ```

2. **查看资源占用**：
   ```bash
   ssh ... "docker stats tech-dns --no-stream --format 'CPU: {{.CPUPerc}}  内存: {{.MemUsage}}' 2>/dev/null"
   ```

3. **查看当前域名映射**：
   ```bash
   ssh ... "grep -v '^#' /opt/tech-stack/dns/hosts.lan 2>/dev/null | grep -v '^$' || echo '无有效记录'"
   ```

4. **解析统计 — Top 10 被查询域名**（dnsmasq 日志 `query[A] domain.com from 1.2.3.4` 中第 6 字段是域名）：
   ```bash
   ssh ... "docker logs tech-dns 2>&1 | grep 'query\[' | awk '{print \$6}' | sort | uniq -c | sort -rn | head -10"
   ```
