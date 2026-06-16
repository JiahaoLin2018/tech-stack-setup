# Action: logs

查看 dnsmasq DNS 服务日志（支持本地和远程两种部署模式）。

## 命令格式

```
/setup-dns logs [--host <ip>] [--user <user>] [--password <pass>|--key <path>]
```

## 步骤

1. **查看最近 50 行日志**：
   ```bash
   ssh ... "docker logs tech-dns --tail 50 2>&1"
   ```

2. **如需实时跟踪日志**，提示用户手动执行：
   ```bash
   ssh $USER@$HOST "docker logs tech-dns -f"
   ```

3. **客户端来源统计 — Top 10 查询客户端 IP**（dnsmasq 日志最后一字段是 source IP；如需看 Top 域名见 `/setup-dns status` 第 4 步）：
   ```bash
   ssh ... "docker logs tech-dns 2>&1 | grep 'query\[' | awk '{print \$NF}' | sort | uniq -c | sort -rn | head -10"
   ```
