# setup-nexus — 踩坑记录

> 按「现象 / 根因 / 修复」三段式记录。新增时追加到文件末尾。

## 新增踩坑记录的处理流程

部署过程中遇到的问题：

1. **修复模板**：将 fix 写入 `references/` 配置文件或 `actions/start.md` 流程步骤，确保下次部署自动生效
2. **追加本文件**：按上述三段式格式记录到末尾
3. **同步 start.md**：若涉及新增步骤，更新 `actions/start.md` 并调整步骤编号

---

## P1. 首次启动需等待 60–90 秒

**现象**：容器已启动，但健康检查返回 503 或无响应。

**根因**：Nexus 初始化需要创建数据目录结构和数据库索引，首次启动比后续启动慢。

**修复**：等待健康检查 `start_period: 120s` 超时前多次轮询（`start.md` 步骤 7 已内置重试逻辑）。

---

## P2. admin 初始密码位置

**现象**：不知道管理员密码，无法登录。

**根因**：Nexus 首次启动后在数据目录生成一次性随机密码，完成初始配置向导后密码文件自动删除。

**修复**：
```bash
docker exec tech-nexus cat /nexus-data/admin.password
```
若文件不存在，说明已完成初始登录配置，密码记录在 `env/nexus.md`。

---

## P3. data 目录权限问题

**现象**：容器启动报错 `Permission denied` 或无法写入数据目录。

**根因**：Nexus 容器以 UID=200 运行，宿主机 data 目录需匹配该权限。

**修复**：
```bash
mkdir -p /opt/tech-stack/nexus/data
chmod 755 /opt/tech-stack/nexus/data
chown 200:200 /opt/tech-stack/nexus/data
```

---

## P4. Maven 客户端仓库地址

**现象**：Maven build 无法从 Nexus 拉取依赖。

**根因**：Maven settings.xml 中 mirror URL 使用了 IP+端口，在多机环境下配置不可移植。

**修复**：统一使用域名（通过 infra-nginx 代理）：
```xml
<mirror>
  <id>nexus-central</id>
  <mirrorOf>*</mirrorOf>
  <url>http://nexus.renew.com/repository/maven-public/</url>
</mirror>
```
