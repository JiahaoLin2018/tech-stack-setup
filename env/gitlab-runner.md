# GitLab Runner — 部署报告

| 项目 | 值 |
|------|-----|
| 部署日期 | 2026-03-26 |
| 目标机器 | 192.168.82.93 |
| 部署目录 | /opt/tech-stack/gitlab-runner/ |
| 容器名称 | tech-gitlab-runner |
| 镜像 | harbor.renew.com/library/gitlab-runner:alpine（v18.10.0） |
| Runner 状态 | 已注册，运行中 |

## 端口

| 端口 | 用途 |
|------|------|
| 无暴露端口 | Runner 主动连接 GitLab，无需入站端口 |

## 配置

| 配置项 | 值 |
|--------|-----|
| GitLab URL | http://gitlab.renew.com |
| Runner 名称 | gitlab-runner-01 |
| Executor | docker |
| 默认镜像 | maven:3.9-eclipse-temurin-21 |
| 并发数 | 2 |
| Tags | pdd（在 GitLab UI 中配置） |
| Run untagged | true（在 GitLab UI 中配置） |

## 连接方式

| 方式 | 地址 |
|------|------|
| 容器内命令 | `docker exec -it tech-gitlab-runner gitlab-runner` |
| 查看日志 | `docker logs -f tech-gitlab-runner` |
| 查看注册状态 | `docker exec tech-gitlab-runner gitlab-runner list` |

## 备注

- 镜像已推送到 Harbor：`harbor.renew.com/library/gitlab-runner:alpine`
- 宿主机 Docker 已配置 `insecure-registries: ["harbor.renew.com"]`（HTTP registry 必需）
- 镜像版本 v18.10.0（alpine latest），向后兼容 GitLab 17.8
- Runner 18.x 注册时 `--tag-list`/`--run-untagged`/`--locked` 等参数已移到 GitLab UI 配置，register 命令不接受这些参数
- 挂载了宿主机 Docker socket，CI 作业可执行 docker build/push
- 宿主机 Harbor 已配置 insecure-registry，CI 作业可直接推送到 harbor.renew.com
- Docker daemon.json 已添加 `insecure-registries: ["harbor.renew.com"]`
- 配置文件：`/opt/tech-stack/gitlab-runner/config/config.toml`
