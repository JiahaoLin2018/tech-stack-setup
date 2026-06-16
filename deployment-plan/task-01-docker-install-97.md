# Task 01 — 安装 Docker (192.168.82.97)

- **状态**: ✅ 完成
- **目标机器**: 192.168.82.97 (Server B — 研发工具)
- **前置依赖**: 无

## 执行内容

与 Task 00 相同，在 97 机器上安装 Docker + Docker Compose。

## 关键命令

```bash
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

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

systemctl enable docker && systemctl start docker
docker --version && docker compose version && docker run --rm hello-world
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
