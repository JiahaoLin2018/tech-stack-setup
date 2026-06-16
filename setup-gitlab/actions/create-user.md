# action: create-user — 创建 GitLab 用户账号

> 由于 GitLab 默认禁用公开注册，用户账号需由管理员手动创建。

## 本地模式（HOST = localhost 或 127.0.0.1）

### 方法一：Web UI 创建（推荐）

1. 登录 GitLab 管理后台：`http://localhost:${GITLAB_HTTP_PORT}`
2. 进入 **Admin → Users → New user**
3. 填写用户信息：
   - Name：用户显示名称
   - Username：用户名（登录用）
   - Email：邮箱地址
   - Password：初始密码（勾选 "Create personal project" 可选）
4. 点击 **Create user**

### 方法二：GitLab Rails Console（内存充足时）

```bash
# 进入 Rails console
docker exec -it tech-gitlab gitlab-rails console

# 创建用户
user = User.new(
  username: 'zhangsan',
  name: '张三',
  email: 'zhangsan@example.com',
  password: 'SecurePassword123!',
  password_confirmation: 'SecurePassword123!',
  skip_confirmation: true
)
user.save!

# 设置为管理员（可选）
user.admin = true
user.save!

# 退出
exit
```

### 方法三：API 创建（需 access_token）

```bash
# 获取 root 的 access_token
ROOT_PASSWORD="your_root_password"
HTTP_PORT="8929"

ACCESS_TOKEN=$(curl -s "http://localhost:${HTTP_PORT}/oauth/token" \
  --data "grant_type=password&username=root&password=${ROOT_PASSWORD}" \
  | jq -r '.access_token')

# 创建用户
curl -s "http://localhost:${HTTP_PORT}/api/v4/users" \
  --header "Authorization: Bearer ${ACCESS_TOKEN}" \
  --data "username=zhangsan" \
  --data "name=张三" \
  --data "email=zhangsan@example.com" \
  --data "password=SecurePassword123!" \
  --data "skip_confirmation=true"
```

---

## 远程模式（HOST 为非 localhost IP 或域名）

### 方法一：Web UI 创建（推荐）

直接访问远程 GitLab 地址进行操作，与本地模式相同。

### 方法二：通过 SSH 执行 Rails Console

```bash
# 通过 SSH 进入远程容器的 Rails console
ssh [AUTH_OPTS] <SSH_USER>@<HOST> \
  "docker exec -it tech-gitlab gitlab-rails console"

# 后续操作与本地模式相同
```

> **注意**：7.6G 内存的机器上 Rails console 可能因 OOM 无法运行，建议使用 Web UI 或 API 方式。

### 方法三：API 创建

```bash
# 在本地机器上调用远程 API
HOST="<HOST>"
HTTP_PORT="<GITLAB_HTTP_PORT>"
ROOT_PASSWORD="your_root_password"

ACCESS_TOKEN=$(curl -s "http://${HOST}:${HTTP_PORT}/oauth/token" \
  --data "grant_type=password&username=root&password=${ROOT_PASSWORD}" \
  | jq -r '.access_token')

curl -s "http://${HOST}:${HTTP_PORT}/api/v4/users" \
  --header "Authorization: Bearer ${ACCESS_TOKEN}" \
  --data "username=zhangsan" \
  --data "name=张三" \
  --data "email=zhangsan@example.com" \
  --data "password=SecurePassword123!" \
  --data "skip_confirmation=true"
```

---

## 批量创建用户

创建 CSV 文件 `users.csv`：

```csv
username,name,email,password
zhangsan,张三,zhangsan@example.com,Pass123!
lisi,李四,lisi@example.com,Pass123!
wangwu,王五,wangwu@example.com,Pass123!
```

执行批量创建脚本：

```bash
ACCESS_TOKEN="your_access_token"
HTTP_PORT="8929"

while IFS=, read -r username name email password; do
  # 跳过表头
  [ "$username" = "username" ] && continue

  curl -s "http://localhost:${HTTP_PORT}/api/v4/users" \
    --header "Authorization: Bearer ${ACCESS_TOKEN}" \
    --data "username=${username}" \
    --data "name=${name}" \
    --data "email=${email}" \
    --data "password=${password}" \
    --data "skip_confirmation=true"

  echo "Created: ${username}"
done < users.csv
```

---

## 用户权限级别

| 级别 | 说明 |
|------|------|
| Guest | 访客，可查看公开项目 |
| Reporter | 报告者，可查看和创建 Issue |
| Developer | 开发者，可推送代码 |
| Maintainer | 维护者，可管理项目设置 |
| Owner | 所有者，拥有完全控制权（组级别） |

---

## 开放注册（可选）

如需开放公开注册，修改 `config/gitlab.rb`：

```ruby
gitlab_rails['gitlab_signup_enabled'] = true
```

然后应用配置：

```bash
docker exec tech-gitlab gitlab-ctl reconfigure
```

> **安全警告**：开放注册可能导致垃圾账号注册，建议仅在内部网络或受信任环境中开放。
