# setup-harbor — 踩坑记录

> 按「现象 / 根因 / 修复」三段式记录。新增时追加到文件末尾。

## 新增踩坑记录的处理流程

部署过程中遇到的问题：

1. **修复模板**：将 fix 写入 `references/` 配置文件或 `actions/start.md` 流程步骤，确保下次部署自动生效
2. **追加本文件**：按上述三段式格式记录到末尾
3. **同步 start.md**：若涉及新增步骤，更新 `actions/start.md` 并调整步骤编号

---

## P1. harbor.yml 必须包含完整必需字段

**现象**：执行 `./prepare` 报错 `KeyError: 'job_loggers'` 或 `KeyError: 'logger_sweeper_duration'`。

**根因**：Harbor 2.12.0 的 `harbor.yml` 必须包含以下字段，否则 prepare 生成的配置不完整：
- `jobservice.job_loggers` — 日志后端配置（`STD_OUTPUT`、`FILE`）
- `jobservice.logger_sweeper_duration` — 日志清理周期
- `_version` — 版本标识

**修复**：已在 `conf/harbor.yml.tpl` 中补充完整配置，部署时务必使用完整模板。

---

## P2. Docker 服务重启后 Harbor 需手动恢复（偶发）

**现象**：执行 `systemctl restart docker` 后，`harbor-core` 容器 Exited，`harbor-jobservice` 不断重启。

**根因**：Docker 服务重启时 Harbor 各组件正在优雅退出，部分容器可能未正确恢复。Harbor 官方安装器已配置 `restart: always`，但偶发情况下需要手动干预。

**修复**：
```bash
cd /opt/tech-stack/harbor/harbor && docker compose start
```

---

## P3. HTTP Registry 需配置 insecure-registries

**现象**：`docker login harbor.renew.com` 报错 `https://harbor.renew.com/v2/: connection refused`。

**根因**：Harbor 通过 infra-nginx 代理在 HTTP :80 端口提供服务，但 Docker 默认尝试 HTTPS（端口 443）。

**修复**：在客户端 `/etc/docker/daemon.json` 添加：
```json
{
  "insecure-registries": ["harbor.renew.com"]
}
```
修改后执行 `systemctl restart docker`。

> **说明**：统一使用域名（无端口），通过 infra-nginx 代理访问 Harbor，多机部署时无需关心 Harbor 实际端口。

---

## P4. 安装包必须手工下载后上传

**现象**：远程服务器无法直接从 GitHub 下载安装包（网络限制或超时）。

**修复**：必须手工下载安装包后上传到服务器，详见 `actions/start.md` 步骤 5。

---

## P5. 端口变更时必须重新执行 prepare

**现象**：修改 harbor.yml 中端口后，容器启动仍使用旧端口。

**根因**：Harbor 通过 `./prepare` 生成最终配置，直接修改 docker-compose.yml 而不重新 prepare 不生效。

**修复**：
1. 修改 `.env` 中 `HARBOR_HTTP_PORT`
2. `envsubst` 重新生成 `harbor.yml`
3. 执行 `./prepare` 重新生成配置
4. 执行 `docker compose down && docker compose up -d`

---

## P6. 生产环境 HTTPS 配置

**现象**：Docker 客户端访问 Harbor 时持续提示 insecure-registries 警告，或生产环境要求使用 HTTPS。

**根因**：Harbor 默认使用 HTTP 模式，生产环境建议启用 HTTPS 以提高安全性。

**修复**：

1. 准备 SSL 证书（推荐使用内部 CA 或 Let's Encrypt）
2. 修改 `harbor.yml` 启用 HTTPS：

```yaml
https:
  port: 443
  certificate: /path/to/harbor.crt
  private_key: /path/to/harbor.key
```

3. 重新执行安装：`./install.sh --with-trivy`
4. 更新客户端 Docker 配置，移除 `insecure-registries` 中的 `harbor.renew.com`

> **说明**：启用 HTTPS 后，Docker 客户端无需配置 `insecure-registries`，可直接 `docker login harbor.renew.com`。
