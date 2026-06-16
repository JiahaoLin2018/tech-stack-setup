# action: activate — 激活 GitLab EE 许可证

## 前置检查：全局唯一服务拒绝 --env 参数

```bash
# 本 skill 为 C 类全局唯一服务，不接受 --env 参数
if [ -n "${ENV}" ]; then
  echo "ERROR: setup-gitlab is a global-unique service and does not accept --env"
  exit 1
fi
```

## 本地模式（HOST = localhost 或 127.0.0.1）

### 步骤 1：检查容器运行状态

```bash
CONTAINER_STATUS=$(docker inspect tech-gitlab --format "{{.State.Status}}" 2>/dev/null)
echo "容器状态：${CONTAINER_STATUS:-不存在}"
```

若容器不存在或状态非 running，提示用户先执行 `/setup-gitlab start`，终止流程。

### 步骤 2：检查是否已激活

```bash
GITLAB_DIR="/opt/tech-stack/gitlab"
LICENSE_DIR="$GITLAB_DIR/license"

if [ -f "$LICENSE_DIR/GitLabBV.gitlab-license" ] && [ -f "$LICENSE_DIR/license_key.pub" ]; then
  echo "检测到已有许可证文件：$LICENSE_DIR/"
  echo "如需重新激活，请先删除 $LICENSE_DIR/ 目录后重新执行"
fi
```

### 步骤 3：在容器内生成许可证（关键）

> **最佳实践**：在容器内生成密钥对和许可证，确保公钥、私钥、许可证三者一致。参见 SKILL.md 踩坑 #6。

```bash
GITLAB_DIR="/opt/tech-stack/gitlab"
LICENSE_DIR="$GITLAB_DIR/license"

# 创建许可证目录
mkdir -p "$LICENSE_DIR"

# 在容器内生成许可证
docker exec tech-gitlab bash -c '
cd /tmp
cat > generate_license.rb << "EOF"
require "openssl"
require "gitlab/license"

# 生成 RSA 2048 密钥对
key = OpenSSL::PKey::RSA.generate(2048)
File.write("license_key", key.to_pem)
File.write("license_key.pub", key.public_key.to_pem)

# 使用私钥签发许可证
Gitlab::License.encryption_key = key

license = Gitlab::License.new
license.licensee = {
  "Name" => "Tech Stack Team",
  "Company" => "Tech Stack",
  "Email" => "admin@tech-stack.local"
}
license.starts_at = Date.new(2025, 1, 1)
license.expires_at = Date.new(2055, 1, 1)
license.notify_admins_at = Date.new(2054, 12, 1)
license.notify_users_at = Date.new(2054, 12, 1)
license.block_changes_at = Date.new(2055, 1, 1)

# 关键：必须设置 plan 为 ultimate
license.restrictions = {
  active_user_count: 10000,
  plan: "ultimate"
}

data = license.export
File.write("GitLabBV.gitlab-license", data)

puts "License generated: plan=ultimate, expires=2055-01-01"
EOF

/opt/gitlab/embedded/bin/ruby generate_license.rb
'
```

> **注意**：如容器内 Ruby 环境不可用，请检查容器状态。

### 步骤 4：复制文件到宿主机

```bash
# 复制密钥和许可证到宿主机
docker cp tech-gitlab:/tmp/license_key.pub "$LICENSE_DIR/"
docker cp tech-gitlab:/tmp/license_key "$LICENSE_DIR/"
docker cp tech-gitlab:/tmp/GitLabBV.gitlab-license "$LICENSE_DIR/"

# 验证文件已生成
ls -la "$LICENSE_DIR/"

# 验证文件类型正确
file "$LICENSE_DIR"/*
# 期望输出：
#   GitLabBV.gitlab-license: ASCII text
#   license_key: PEM RSA private key
#   license_key.pub: ASCII text
```

### 步骤 5：重启容器加载公钥

```bash
cd "$GITLAB_DIR"
# docker-compose.yml 默认已挂载 license_key.pub（首次部署 start 已 touch 占位空文件）
# 此时 license_key.pub 已被真实公钥覆盖，restart 后 GitLab 加载新公钥
docker compose restart
echo "容器已重启，等待 GitLab 加载新公钥..."
```

等待 GitLab 启动（约 2-3 分钟）：

```bash
for i in $(seq 1 30); do
  STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${GITLAB_HTTP_PORT:-8929}/ --connect-timeout 5 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "302" ]; then
    echo "GitLab 已就绪"
    break
  fi
  echo "等待中... ($i/30) HTTP: $STATUS"
  sleep 10
done
```

### 步骤 6：验证公钥挂载

```bash
# 检查容器内和宿主机公钥 MD5 是否一致
CONTAINER_MD5=$(docker exec tech-gitlab md5sum /opt/gitlab/embedded/service/gitlab-rails/.license_encryption_key.pub 2>/dev/null | awk '{print $1}')
HOST_MD5=$(md5sum "$LICENSE_DIR/license_key.pub" | awk '{print $1}')

if [ "$CONTAINER_MD5" = "$HOST_MD5" ]; then
  echo "✓ 公钥挂载正确: $CONTAINER_MD5"
else
  echo "✗ 公钥不匹配！容器内: $CONTAINER_MD5, 宿主机: $HOST_MD5"
  echo "请检查 docker-compose.yml 中的 volume 挂载配置"
fi
```

### 步骤 7：导入许可证

**方式 A：Rails console 直接保存（推荐）**

> **关键**：API 上传可能失败，直接通过 Rails model 保存更可靠。参见 SKILL.md 踩坑 #7。

```bash
# 复制许可证到容器
docker cp "$LICENSE_DIR/GitLabBV.gitlab-license" tech-gitlab:/tmp/

# 通过 Rails console 保存
docker exec tech-gitlab gitlab-rails runner "
license_data = File.read('/tmp/GitLabBV.gitlab-license')
lic = License.new(data: license_data)
if lic.save
  puts '✓ 许可证保存成功'
  puts '  ID: ' + lic.id.to_s
  puts '  Plan: ' + lic.plan
  puts '  Expires: ' + lic.expires_at.to_s
else
  puts '✗ 保存失败: ' + lic.errors.full_messages.to_s
end
"
```

**方式 B：Web UI 手动上传（备选）**

如 Rails console 因内存不足无法运行：

```
1. 登录 GitLab 管理后台：http://localhost:${GITLAB_HTTP_PORT:-8929}
2. 进入 Admin → Settings → General → Add License
3. 上传许可证文件：/opt/tech-stack/gitlab/license/GitLabBV.gitlab-license
```

### 步骤 8：验证许可证状态

```bash
# 通过 Rails console 验证
docker exec tech-gitlab gitlab-rails runner "
lic = License.current
if lic
  puts '=== 许可证信息 ==='
  puts 'Plan: ' + lic.plan
  puts 'Expires: ' + lic.expires_at.to_s
  puts 'Active users: ' + lic.restrictions['active_user_count'].to_s
else
  puts '未找到许可证'
end
" 2>&1 | grep -E '^(Plan|Expires|Active|未找到|===)'
```

**期望输出**：
```
=== 许可证信息 ===
Plan: ultimate
Expires: 2055-01-01
Active users: 10000
```

### 步骤 9：展示激活结果

```
==========================================
GitLab EE 许可证激活完成！
==========================================

许可证信息：
  计划：Ultimate
  有效期：2025-01-01 ~ 2055-01-01
  用户数：10000

持久化状态：已启用
  - 宿主机重启 / docker restart      → 无需重新激活
  - docker compose down + up（重建）  → 无需重新激活
  - GitLab 镜像升级                   → 无需重新激活

仅以下情况需要重新执行 activate：
  - 手动删除了 license/ 目录
  - 手动移除了 docker-compose.yml 中的公钥挂载行

许可证文件位置：/opt/tech-stack/gitlab/license/
  - license_key              (私钥，请妥善保管)
  - license_key.pub          (已挂载至容器内)
  - GitLabBV.gitlab-license  (许可证文件)

Epic 功能位于 Group 级别（非 Project 级别）
```

---

## 远程模式（HOST 为非 localhost IP 或域名）

### 步骤 1：测试 SSH 连通性

```bash
ssh [AUTH_OPTS] -o ConnectTimeout=10 -p <SSH_PORT> <SSH_USER>@<HOST> "echo SSH连接成功"
```

### 步骤 2：检查远程容器状态和部署目录

```bash
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> "
  [ -d /opt/tech-stack/gitlab ] || { echo 'GitLab 部署目录不存在，请先 /setup-gitlab start'; exit 1; }
  STATUS=\$(docker inspect tech-gitlab --format '{{.State.Status}}' 2>/dev/null || echo '不存在')
  echo \"容器状态：\$STATUS\"
  [ \"\$STATUS\" = \"running\" ] || { echo '容器未运行，终止激活流程'; exit 1; }
"
```

### 步骤 3：远程执行完整激活流程

通过 SSH 把本地模式的步骤 3-8 整体推送到远端 bash 执行。`<< 'REMOTE_EOF'` 单引号阻止本地 shell 扩展，所有变量在远端解析。

```bash
ssh [AUTH_OPTS] -p <SSH_PORT> <SSH_USER>@<HOST> bash << 'REMOTE_EOF'
set -e
GITLAB_DIR="/opt/tech-stack/gitlab"
LICENSE_DIR="$GITLAB_DIR/license"
mkdir -p "$LICENSE_DIR"

# 在容器内生成密钥对和许可证
docker exec tech-gitlab bash -c '
cd /tmp
cat > generate_license.rb << "RUBY_EOF"
require "openssl"
require "gitlab/license"

key = OpenSSL::PKey::RSA.generate(2048)
File.write("license_key", key.to_pem)
File.write("license_key.pub", key.public_key.to_pem)

Gitlab::License.encryption_key = key

license = Gitlab::License.new
license.licensee = {
  "Name" => "Tech Stack Team",
  "Company" => "Tech Stack",
  "Email" => "admin@tech-stack.local"
}
license.starts_at = Date.new(2025, 1, 1)
license.expires_at = Date.new(2055, 1, 1)
license.notify_admins_at = Date.new(2054, 12, 1)
license.notify_users_at = Date.new(2054, 12, 1)
license.block_changes_at = Date.new(2055, 1, 1)
license.restrictions = { active_user_count: 10000, plan: "ultimate" }

File.write("GitLabBV.gitlab-license", license.export)
puts "License generated"
RUBY_EOF
/opt/gitlab/embedded/bin/ruby generate_license.rb
'

# 复制密钥和许可证到宿主机
docker cp tech-gitlab:/tmp/license_key.pub "$LICENSE_DIR/"
docker cp tech-gitlab:/tmp/license_key "$LICENSE_DIR/"
docker cp tech-gitlab:/tmp/GitLabBV.gitlab-license "$LICENSE_DIR/"

# 重启容器使容器内挂载点加载新公钥
cd "$GITLAB_DIR" && docker compose restart

# 等待 GitLab 就绪
set -a && source .env && set +a
for i in $(seq 1 30); do
  STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${GITLAB_HTTP_PORT:-8929}/ --connect-timeout 5 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "302" ]; then break; fi
  echo "等待中... ($i/30) HTTP: $STATUS"
  sleep 10
done

# 验证公钥 MD5 一致
CONTAINER_MD5=$(docker exec tech-gitlab md5sum /opt/gitlab/embedded/service/gitlab-rails/.license_encryption_key.pub 2>/dev/null | awk '{print $1}')
HOST_MD5=$(md5sum "$LICENSE_DIR/license_key.pub" | awk '{print $1}')
[ "$CONTAINER_MD5" = "$HOST_MD5" ] && echo "公钥挂载正确" || echo "WARNING: 公钥不一致"

# 导入许可证
docker cp "$LICENSE_DIR/GitLabBV.gitlab-license" tech-gitlab:/tmp/
docker exec tech-gitlab gitlab-rails runner "
license_data = File.read('/tmp/GitLabBV.gitlab-license')
lic = License.new(data: license_data)
puts lic.save ? '✓ License saved: ' + lic.plan : '✗ ' + lic.errors.full_messages.to_s
"

# 验证许可证状态
docker exec tech-gitlab gitlab-rails runner "
lic = License.current
puts 'Plan: ' + lic.plan
puts 'Expires: ' + lic.expires_at.to_s
"
REMOTE_EOF
```

---

## 验证 Epic 功能

Epic 功能属于 Ultimate 计划，位于 **Group 级别**（非 Project 级别）：

1. 创建或进入一个 Group
2. 左侧菜单应出现 **Epics** 选项
3. 如无 Epics 菜单，检查：
   - 许可证 Plan 是否为 Ultimate
   - Group 设置：Settings → General → Permissions and features
