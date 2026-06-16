# Harbor 生产配置模板
# 变量通过 .env 文件定义，使用 envsubst 自动生成最终配置
# 参考文档：https://goharbor.io/docs/2.12.0/install-config/configure-yml-file/

hostname: ${HARBOR_HOSTNAME}

# HTTP（仅内网/测试用，生产必须使用 HTTPS）
http:
  port: ${HARBOR_HTTP_PORT}

# HTTPS（生产必须启用，需提前准备证书）
# 如无证书，可用 Let's Encrypt 或 mkcert 生成自签名证书
# 启用 HTTPS 时取消以下注释并填入实际证书路径：
# https:
#   port: ${HARBOR_HTTPS_PORT}
#   certificate: /your/cert/path/harbor.crt
#   private_key: /your/cert/path/harbor.key

# 管理员密码（首次安装后通过 Web UI 修改更安全）
harbor_admin_password: ${HARBOR_ADMIN_PASSWORD}

# 数据库配置
database:
  password: ${HARBOR_DB_PASSWORD}
  max_idle_conns: 100
  max_open_conns: 900
  conn_max_lifetime: 5m
  conn_max_idle_time: 0

# 数据存储路径（确保磁盘空间充足）
data_volume: ${HARBOR_DATA_DIR}

# Trivy 漏洞扫描（推荐启用）
trivy:
  ignore_unfixed: false
  skip_update: false
  skip_java_db_update: false
  offline_scan: false
  security_check: vuln
  insecure: false
  timeout: 5m0s

# Job Service 并发配置（必须包含 job_loggers 和 logger_sweeper_duration）
jobservice:
  max_job_workers: 10
  job_loggers:
    - STD_OUTPUT
    - FILE
  logger_sweeper_duration: 1

# Webhook 通知重试
notification:
  webhook_job_max_retry: 3
  webhook_job_http_client_timeout: 3

# 日志配置
log:
  level: info
  local:
    rotate_count: 50
    rotate_size: 200M
    location: /var/log/harbor

# 版本标识（必须与安装包版本一致）
_version: 2.12.0

# Proxy 缓存（可选，用于代理公共镜像仓库）
proxy:
  http_proxy:
  https_proxy:
  no_proxy:
  components:
    - core
    - jobservice
    - trivy

# 清理上传临时文件
upload_purging:
  enabled: true
  age: 168h
  interval: 24h
  dryrun: false

# 缓存层配置
cache:
  enabled: false
  expire_hours: 24
