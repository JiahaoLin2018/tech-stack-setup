# action: verify — 验证 Nexus

## 步骤

```bash
SSH_CMD "curl -s http://localhost:${NEXUS_PORT:-8081}/service/rest/v1/status"
SSH_CMD "curl -s -o /dev/null -w '%{http_code}' http://localhost:${NEXUS_PORT:-8081}/"
SSH_CMD "docker exec tech-nexus cat /nexus-data/admin.password 2>/dev/null || echo '密码文件不存在'"
```

## Maven settings.xml 配置示例

完成 Nexus 初始化后，在 `~/.m2/settings.xml` 中添加：

```xml
<settings>
  <mirrors>
    <mirror>
      <id>nexus</id>
      <mirrorOf>*</mirrorOf>
      <url>http://nexus.renew.com/repository/maven-public/</url>
    </mirror>
  </mirrors>
  <servers>
    <server>
      <id>nexus</id>
      <username>admin</username>
      <password>YOUR_PASSWORD</password>
    </server>
    <server>
      <id>nexus-releases</id>
      <username>admin</username>
      <password>YOUR_PASSWORD</password>
    </server>
    <server>
      <id>nexus-snapshots</id>
      <username>admin</username>
      <password>YOUR_PASSWORD</password>
    </server>
  </servers>
</settings>
```

项目 `pom.xml` 分发配置：

```xml
<distributionManagement>
  <repository>
    <id>nexus-releases</id>
    <url>http://nexus.renew.com/repository/maven-releases/</url>
  </repository>
  <snapshotRepository>
    <id>nexus-snapshots</id>
    <url>http://nexus.renew.com/repository/maven-snapshots/</url>
  </snapshotRepository>
</distributionManagement>
```

## 故障排查

| 问题 | 可能原因 | 处理建议 |
|------|---------|---------|
| HTTP 503 | 服务未完全启动 | 等待 30 秒后重试 |
| 容器无响应 | 内存不足，OOM 终止 | 增加 Docker 内存限制或调小 JVM 参数 |
| 数据目录权限错误 | uid=200 写入失败 | `chmod 755 /opt/tech-stack/nexus/data` |
| admin.password 不存在 | 已完成首次登录 | 使用已设置的管理员密码 |
