# 使用 Harbor 基础镜像
# 注意：app.sh 会优先使用项目中的 Dockerfile，而非自动生成
FROM harbor.renew.com/library/nginx:1.27

# 复制 nginx 配置（由 app.sh 生成）
COPY nginx.default.conf /etc/nginx/conf.d/default.conf

# 复制静态页面（dist 目录由 CI 构建）
COPY dist/ /usr/share/nginx/html/

# 健康检查
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -sf http://localhost/ || exit 1

# 暴露端口
EXPOSE 80

# 启动 nginx
CMD ["nginx", "-g", "daemon off;"]
