# Action: stop

停止 dnsmasq DNS 服务（支持本地和远程两种部署模式）。

## 命令格式

```
/setup-dns stop [--host <ip>] [--user <user>] [--password <pass>|--key <path>]
```

## 步骤

1. **远程停止**：
   ```bash
   ssh ... "cd /opt/tech-stack/dns && docker compose stop"
   ```

2. **确认结果**（容器保留以便快速 start 恢复，仅校验状态为 exited）：
   ```bash
   ssh ... "STATUS=\$(docker inspect tech-dns --format='{{.State.Status}}' 2>/dev/null); \
     case \"\$STATUS\" in \
       exited) echo '✅ dnsmasq 容器已停止（status=exited）' ;; \
       running) echo '❌ dnsmasq 容器仍在运行' ;; \
       '') echo 'ℹ️  容器不存在（已被移除）' ;; \
       *) echo \"⚠️  状态异常: \$STATUS\" ;; \
     esac"
   ```

3. **重要提示**：
   ```
   ⚠️  远程 DNS 服务已停止！所有指向此 DNS 的机器将无法解析 *.renew.com 域名。
   📁 远程配置文件保留在 /opt/tech-stack/dns/，重新 start 后自动恢复。
   ```
