-- ========================================
-- 业务 MySQL 初始化脚本
-- 1. 限制 root 本地登录
-- 2. 创建 exporter 监控用户
-- 3. 为 appuser 授予建库权限
-- ========================================
-- 每个环境（dev/sit/fat/uat/prod）为独立实例，业务 DB 名称建议以环境为前缀（如 dev_order）。
-- 本脚本不创建任何业务 DB，由应用启动时按 Apollo 配置自行创建。

-- 1. 限制 root 只能从本地登录（安全加固）
DELETE FROM mysql.user WHERE User='root' AND Host != 'localhost';
FLUSH PRIVILEGES;

-- 2. 创建 mysqld_exporter 专用监控用户
-- root 已限制为 localhost 登录，exporter 从容器网络连接需要独立用户
-- 密码必须与 conf/exporter.my.cnf 中的 password 一致
CREATE USER IF NOT EXISTS 'exporter'@'%' IDENTIFIED BY 'CHANGE_ME_EXPORTER_PASSWORD';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';

-- 3. 为 appuser 授予所有库的权限（允许应用创建业务库）
GRANT ALL PRIVILEGES ON `%`.* TO 'appuser'@'%';

FLUSH PRIVILEGES;
