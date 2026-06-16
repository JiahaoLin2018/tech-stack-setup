# Task 00 — 安装 Docker (192.168.82.93)

- **状态**: ✅ 完成
- **目标机器**: 192.168.82.93 (Server A — 基础设施)
- **前置依赖**: 无

## 执行内容

1. 检查是否已安装 Docker（上次检查结果：未安装）
2. 安装 Docker Engine（CentOS 7）
3. 安装 Docker Compose v2 插件
4. 配置 Docker daemon（镜像加速、日志限制）
5. 启动 Docker 并设置开机自启
6. 验证安装

## 关键命令

```bash
# 安装依赖
yum install -y yum-utils device-mapper-persistent-data lvm2

# 添加 Docker 仓库
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# 安装 Docker
yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 配置 daemon.json（日志限制，避免磁盘撑满）
cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

# 启动
systemctl enable docker && systemctl start docker

# 验证
docker --version
docker compose version
docker run --rm hello-world
```

## 验证标准

- [ ] `docker --version` 输出版本号
- [ ] `docker compose version` 输出版本号
- [ ] `docker run --rm hello-world` 正常输出
- [ ] `systemctl is-enabled docker` 输出 `enabled`

## 完成记录

- 开始时间:
- 完成时间:
- 备注:
