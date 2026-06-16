# action: logs — 查看 Nexus 日志

## 步骤

```bash
SSH_CMD "docker logs tech-nexus --tail 50"
```

实时跟踪（通过 SSH 管道）：

```bash
# 密码模式
sshpass -p "${SSH_PASSWORD}" ssh -t -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} \
  "docker logs tech-nexus --tail 50 -f"

# 密钥模式
ssh -i ${SSH_KEY_PATH} -t -p ${SSH_PORT:-22} ${SSH_USER:-root}@${HOST} \
  "docker logs tech-nexus --tail 50 -f"
```

## 常见错误日志排查

| 日志关键字 | 可能原因 | 处理建议 |
|-----------|---------|---------|
| `java.lang.OutOfMemoryError` | JVM 堆内存不足 | 增加 Docker 内存，或调整 .env 中 `NEXUS_JVM_MAX_HEAP` |
| `port is already allocated` | 8081/8082 端口冲突 | 修改 .env 中 `NEXUS_PORT` 后重启 |
| `Permission denied` 在 `/nexus-data` | 数据目录权限不足 | `chmod 755 /opt/tech-stack/nexus/data` |
| `Address already in use` | Nexus 进程重复启动 | 先执行 stop，再执行 start |
| `ERROR StatusLogger` | Log4j 配置警告（可忽略） | 不影响运行，属于正常启动输出 |
