# ========================================
# GitLab 配置文件（模板）
# ========================================
# 此文件通过 envsubst 从环境变量生成
# 修改后执行：docker exec tech-gitlab gitlab-ctl reconfigure
# ========================================

# ========================================
# 外部访问 URL（从环境变量注入）
# ========================================
external_url 'http://${GITLAB_HOSTNAME}'

# ========================================
# 基础配置
# ========================================

# 时区
gitlab_rails['time_zone'] = 'Asia/Shanghai'

# SSH 端口（从环境变量注入）
gitlab_rails['gitlab_shell_ssh_port'] = ${GITLAB_SSH_PORT}

# ========================================
# 安全配置
# ========================================

# 禁用公开注册（用户账号由管理员统一分配）
gitlab_rails['gitlab_signup_enabled'] = false

# ========================================
# 备份配置
# ========================================

# 备份保留时间（秒），默认 7 天
gitlab_rails['backup_keep_time'] = 604800

# 备份路径
gitlab_rails['backup_path'] = "/var/opt/gitlab/backups"

# ========================================
# 性能调优
# ========================================

# Puma 工作进程数（默认 2，内存充足可增加）
puma['worker_processes'] = 2

# Sidekiq 最大并发数
sidekiq['max_concurrency'] = 10

# PostgreSQL 共享缓冲区
postgresql['shared_buffers'] = "256MB"

# ========================================
# 内置服务
# ========================================

# 关闭内置 Prometheus 监控（使用外部 Prometheus）
prometheus_monitoring['enable'] = false

# ========================================
# SMTP 配置（生产环境必须配置）
# ========================================
# 取消以下注释并填写真实信息：

# gitlab_rails['smtp_enable'] = true
# gitlab_rails['smtp_address'] = "smtp.example.com"
# gitlab_rails['smtp_port'] = 587
# gitlab_rails['smtp_user_name'] = "noreply@example.com"
# gitlab_rails['smtp_password'] = "CHANGE_ME"
# gitlab_rails['smtp_domain'] = "example.com"
# gitlab_rails['smtp_authentication'] = "login"
# gitlab_rails['smtp_enable_starttls_auto'] = true
# gitlab_rails['gitlab_email_from'] = 'noreply@example.com'
