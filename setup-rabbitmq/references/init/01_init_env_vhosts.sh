#!/bin/bash
# ========================================
# RabbitMQ 应用级 vhost 初始化脚本（可选）
#
# 架构说明：
#   每个环境（dev/sit/fat/uat/prod）已部署独立 RabbitMQ 实例，实例之间物理隔离。
#   Spring Boot 业务应用默认使用 vhost `/`（已完全隔离，无需额外 vhost）。
#
#   本脚本用于在单个实例内为不同应用创建专属 vhost（可选，按需执行）。
#
# 使用方式（首次部署后按需执行）：
#   docker exec tech-rabbitmq-${ENV} bash /init/01_init_env_vhosts.sh
# ========================================

set -e

echo "Initializing application vhosts in this RabbitMQ instance..."

# 创建应用专属 vhost 并为 admin 用户授权（按需修改 vhost 列表）
for vhost in app1 app2; do
    if rabbitmqctl list_vhosts | grep -q "^/${vhost}$"; then
        echo "vhost /${vhost} already exists, skipping"
    else
        rabbitmqctl add_vhost /${vhost}
        rabbitmqctl set_permissions -p /${vhost} admin ".*" ".*" ".*"
        echo "vhost /${vhost} created"
    fi
done

echo "Done. Application vhosts initialized."
