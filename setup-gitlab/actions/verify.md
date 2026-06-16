# action: verify — 验证 GitLab 服务

## 步骤

### 步骤 1：测试 SSH 连通性

```bash
ssh [AUTH_OPTS] -o ConnectTimeout=10 -p <SSH_PORT> <SSH_USER>@<HOST> "echo SSH连接成功"
```

### 步骤 2：远程检查容器状态

```bash
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "docker inspect tech-gitlab --format '{{.State.Status}}' 2>/dev/null || echo '不存在'"
```

### 步骤 3：远程检查内部服务

```bash
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> \
  "docker exec tech-gitlab gitlab-ctl status 2>/dev/null | grep -E '^(run|down):'"
```

### 步骤 4：远程 HTTP 可访问性检查

```bash
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  set -a && source /opt/tech-stack/gitlab/.env && set +a
  curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://localhost:\${GITLAB_HTTP_PORT:-8929}/ 2>/dev/null
"
```

输出结果时将地址替换为 `http://<HOST>:${GITLAB_HTTP_PORT}`。

---

## 完整验证报告

> 部署成功后执行以下验证，确保所有功能正常。

### 1. 注册功能验证

默认配置已禁用公开注册，验证如下：

```bash
# 方法一：检查配置文件
ssh [AUTH_OPTS] <SSH_USER>@<HOST> \
  "grep 'signup_enabled' /opt/tech-stack/gitlab/config/gitlab.rb"
# 期望输出：gitlab_rails['gitlab_signup_enabled'] = false

# 方法二：检查登录页面注册链接数量
ssh [AUTH_OPTS] <SSH_USER>@<HOST> "
  set -a && source /opt/tech-stack/gitlab/.env && set +a
  curl -s http://localhost:\${GITLAB_HTTP_PORT:-8929}/users/sign_in | grep -c 'sign_up'
"
# 期望输出：0（表示已禁用）

# 方法三：Web UI 验证
# 访问 http://<HOST>:${GITLAB_HTTP_PORT}/users/sign_in
# 页面底部应无 "Register now" 链接
```

验证结果表格：

| 检查项 | 期望状态 | 说明 |
|--------|----------|------|
| 配置文件 | ✅ | `gitlab_signup_enabled = false` |
| 登录页面注册链接 | ✅ | 数量为 0，已移除 |
| 配置持久化位置 | ✅ | `/opt/tech-stack/gitlab/config/gitlab.rb` |

### 2. GitLab EE 许可证验证

```bash
# 方法一：检查许可证文件
ssh [AUTH_OPTS] <SSH_USER>@<HOST> \
  "ls -la /opt/tech-stack/gitlab/license/GitLabBV.gitlab-license"
# 期望：文件存在

# 方法二：检查公钥文件
ssh [AUTH_OPTS] <SSH_USER>@<HOST> \
  "ls -la /opt/tech-stack/gitlab/license/license_key.pub"
# 期望：文件存在

# 方法三：检查公钥挂载配置
ssh [AUTH_OPTS] <SSH_USER>@<HOST> \
  "grep -v '^#' /opt/tech-stack/gitlab/docker-compose.yml | grep 'license_key.pub'"
# 期望：显示挂载配置行

# 方法四：检查许可证 Plan（关键）
# 通过 API 查询许可证信息
ssh [AUTH_OPTS] <SSH_USER>@<HOST> "
  cd /opt/tech-stack/gitlab
  set -a && source .env && set +a
  ROOT_PWD=\$(docker exec tech-gitlab cat /etc/gitlab/initial_root_password 2>/dev/null | grep '^Password:' | awk '{print \$2}')
  TOKEN=\$(curl -s \"http://localhost:\${GITLAB_HTTP_PORT}/oauth/token\" -d \"grant_type=password&username=root&password=\${ROOT_PWD}\" | jq -r '.access_token')
  curl -s \"http://localhost:\${GITLAB_HTTP_PORT}/api/v4/license\" -H \"Authorization: Bearer \${TOKEN}\" | jq '{plan, expires_at, active_user_count}'
"
# 期望输出：{"plan": "ultimate", "expires_at": "2055-01-01", "active_user_count": 10000}
```

验证结果表格：

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 许可证文件 | ✅ | `/opt/tech-stack/gitlab/license/GitLabBV.gitlab-license` |
| 公钥文件 | ✅ | `/opt/tech-stack/gitlab/license/license_key.pub` |
| 公钥挂载 | ✅ | docker-compose.yml 已配置 |
| 许可证导入 | ✅ | 通过 Rails console 或 Web UI |
| 许可证 Plan | ⚠️ | **必须为 Ultimate，否则 Epic 功能不可用** |

**手动导入许可证步骤**：

1. 登录 http://<HOST>:${GITLAB_HTTP_PORT}（root / 初始密码）
2. 进入 **Admin → Settings → General → Add License**
3. 上传 `/opt/tech-stack/gitlab/license/GitLabBV.gitlab-license`
4. 保存后可看到许可证信息：
   - Plan: Ultimate
   - 有效期：2025-01-01 ~ 2055-01-01
   - 用户数：10000

> **重要**：如 Plan 显示为 Starter，说明许可证生成时未指定 `plan: "ultimate"`，需重新执行 `activate` action。Epic 功能位于 **Group 级别**，需先创建 Group 后在左侧菜单查看。

### 3. 服务健康检查

```bash
# 容器状态
ssh [AUTH_OPTS] <SSH_USER>@<HOST> \
  "docker ps --filter name=tech-gitlab --format '{{.Names}} {{.Status}}'"
# 期望：Up X minutes (healthy)

# HTTP 响应
ssh [AUTH_OPTS] <SSH_USER>@<HOST> "
  set -a && source /opt/tech-stack/gitlab/.env && set +a
  curl -s -o /dev/null -w '%{http_code}' http://localhost:\${GITLAB_HTTP_PORT:-8929}/
"
# 期望：200 或 302

# 内存使用
ssh [AUTH_OPTS] <SSH_USER>@<HOST> \
  "docker stats --no-stream --format '{{.MemUsage}}' tech-gitlab"
# 期望：在配置的限制范围内（默认 4G）
```

---

## 验证报告输出示例

```
==================================================
GitLab 部署验证报告
==================================================

容器状态: tech-gitlab Up 10 minutes (healthy)
HTTP 状态: 302

--------------------------------------------------
1. 注册功能验证
--------------------------------------------------
配置文件: gitlab_rails['gitlab_signup_enabled'] = false [OK]
登录页面: 注册链接数量 0 [OK]

--------------------------------------------------
2. 许可证验证
--------------------------------------------------
许可证文件: 存在 [OK]
公钥文件: 存在 [OK]
公钥挂载: 已配置 [OK]
许可证导入: 需手动在 Web UI 上传 [待处理]
许可证 Plan: ultimate [OK] ← 关键检查项

--------------------------------------------------
3. 服务健康
--------------------------------------------------
内部服务: 全部运行中 [OK]
内存使用: 3.1GiB / 4GiB [OK]

==================================================
验证完成
==================================================

注意：Epic 功能位于 Group 级别，需先创建 Group 后在左侧菜单查看。
```
