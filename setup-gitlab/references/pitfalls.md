# setup-gitlab — 踩坑记录

> 按「现象 / 根因 / 修复」三段式记录。新增时追加到文件末尾。

## 新增踩坑记录的处理流程

部署过程中遇到的问题：

1. **修复模板**：将 fix 写入 `references/` 或 `actions/`，确保自动生效
2. **追加本文件**：按上述三段式格式记录到末尾

---

## P1. 端口映射错误

**现象**：HTTP 请求返回 000（连接被拒绝），容器状态正常但无法访问。

**根因**：`external_url` 包含端口号时，GitLab 内部 nginx 监听该端口而非默认 80，导致端口映射 `${PORT}:80` 失效。

**修复**（现行）：`external_url 'http://${GITLAB_HOSTNAME}'` 不含端口号，nginx 监听 80；`docker-compose.yml` 端口映射使用 `${GITLAB_HTTP_PORT:-8929}:80`；infra-nginx 代理宿主机 :8929 → 容器 :80。

---

## P2. 健康检查端口错误

**现象**：容器显示 `unhealthy`，但服务实际正常运行。

**根因**：早期 `external_url` 含端口时，GitLab nginx 监听该端口，默认健康检查 `localhost:80` 无响应。

**修复**（现行）：`external_url` 不含端口，nginx 监听 80；健康检查使用 `curl -sf http://localhost/-/readiness?all=1` 直接命中 :80，无需指定端口。

---

## P3. 内存不足

**现象**：Rails console 报错 `Cannot allocate memory`。

**根因**：7.6G 内存机器上 GitLab 占用 4G，剩余不足。

**修复**：
- `.env` 中设置 `GITLAB_MEMORY_LIMIT=4g`
- 内存紧张时通过 Web UI 手动上传许可证（绕过 Rails console）

---

## P4. Ruby 镜像拉取失败

**现象**：拉取 `ruby:3.2-slim` 超时。

**根因**：国内网络无法直接访问 Docker Hub。

**修复**：配置镜像加速器 `/etc/docker/daemon.json`：
```json
{"registry-mirrors": ["https://docker.m.daocloud.io"]}
```

---

## P5. GitLab 配置必须走 gitlab.rb，不能用 GITLAB_OMNIBUS_CONFIG 环境变量

**现象**：修改 `.env` 后重建容器，GitLab 配置不生效。

**根因**：`GITLAB_OMNIBUS_CONFIG` 环境变量存在三个固有缺陷，不适合作为配置入口：

1. **长度限制**：复杂配置会被截断
2. **不持久化**：只在首次启动时生效；`gitlab.rb` 文件存在后环境变量被忽略
3. **配置分散**：部分在 `docker-compose.yml`，部分在 `gitlab.rb`，优先级混乱难以排查

**修复**：
- `docker-compose.yml` 中 `environment: []` 不注入任何 GITLAB_OMNIBUS_CONFIG
- 所有 GitLab 配置写入 `conf/gitlab.rb.tpl`，使用 `envsubst` 从 `.env` 渲染为 `config/gitlab.rb`
- 修改流程：编辑 `config/gitlab.rb` → `docker exec tech-gitlab gitlab-ctl reconfigure`

> envsubst 渲染时仅替换 `${GITLAB_HOSTNAME}` 和 `${GITLAB_SSH_PORT}` 两个占位符，避免污染 Ruby 脚本中的其他 `$` 变量。

---

## P6. 许可证 Plan 默认为 Starter（关键）

**现象**：Epic 等 Ultimate 功能不可用。

**根因**：`license.rb` 未设置 `plan` 字段，默认 `starter`。

**修复**：在 `restrictions` 中显式添加：
```ruby
license.restrictions = {
  active_user_count: 10000,
  plan: "ultimate",
}
```

> **注意**：Epic 功能位于 **Group 级别**（非 Project 级别）。

---

## P7. API 上传许可证失败（关键）

**现象**：`curl -X POST /api/v4/license` 返回 `{"error":"license is invalid"}`，即使公钥/私钥/许可证三者匹配。

**根因**：GitLab License API 有额外校验逻辑。

**修复**：通过 Rails console 直接保存（参见 `actions/activate.md`）：
```bash
docker exec tech-gitlab gitlab-rails runner "
  license_data = File.read('/tmp/GitLabBV.gitlab-license')
  License.new(data: license_data).save!
"
```

---

## P8. 公钥/私钥/许可证不匹配

**现象**：许可证验证失败 `license is invalid`。

**根因**：许可证在容器外生成，密钥对与容器内挂载的公钥不一致。

**修复**：在容器内生成许可证（参见 `actions/activate.md`）：
```bash
# 1. 在容器内生成
docker exec tech-gitlab /opt/gitlab/embedded/bin/ruby generate_license.rb

# 2. 复制到宿主机
docker cp tech-gitlab:/tmp/license_key.pub license/
docker cp tech-gitlab:/tmp/GitLabBV.gitlab-license license/

# 3. 重启容器
docker compose down && docker compose up -d
```

---

## P9. volume 挂载缩进错误

**现象**：公钥挂载不生效，容器内公钥与宿主机不一致。

**根因**：docker-compose.yml 中 volume 行缩进错误。

**验证**：
```bash
docker exec tech-gitlab md5sum /opt/gitlab/embedded/service/gitlab-rails/.license_encryption_key.pub
md5sum license/license_key.pub
# 两者应一致
```

---

## P10. 生产环境 SMTP 配置

**现象**：GitLab 无法发送邮件通知（密码重置、CI/CD 通知等）。

**根因**：`gitlab.rb.tpl` 中 SMTP 配置默认注释，生产环境未启用。

**修复**：取消 `config/gitlab.rb` 中 SMTP 相关配置的注释并填写真实邮件服务器信息：

```ruby
gitlab_rails['smtp_enable'] = true
gitlab_rails['smtp_address'] = "smtp.example.com"
gitlab_rails['smtp_port'] = 587
gitlab_rails['smtp_user_name'] = "noreply@example.com"
gitlab_rails['smtp_password'] = "CHANGE_ME"
gitlab_rails['smtp_domain'] = "example.com"
gitlab_rails['smtp_authentication'] = "login"
gitlab_rails['smtp_enable_starttls_auto'] = true
gitlab_rails['gitlab_email_from'] = 'noreply@example.com'
```

修改后执行：`docker exec tech-gitlab gitlab-ctl reconfigure`

> **注意**：生产环境必须配置 SMTP，否则无法发送密码重置邮件和系统通知。
