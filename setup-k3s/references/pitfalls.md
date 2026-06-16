# setup-k3s 运维记录

## 1. Harbor 镜像拉取失败（ImagePullBackOff）

**现象**：Pod 报错 `ImagePullBackOff`，日志显示 `dial tcp 192.168.x.x:443: connection refused`

**根因**：`registries.yaml` 未配置 Harbor，K3s containerd 默认使用 HTTPS 443 端口连接。

**修复**：在 `/etc/rancher/k3s/registries.yaml` 添加 Harbor HTTP 配置：
```yaml
mirrors:
  harbor.renew.com:
    endpoint:
      - "http://harbor.renew.com"   # 通过 infra-nginx 代理，走 HTTP :80
```
重启 K3s：`systemctl restart k3s`

---

## 2. CoreDNS 配置被 K3s Addon Controller 重置

**现象**：K3s 重启后 CoreDNS 配置丢失，Pod 无法解析 `*.renew.com` 域名。

**根因**：K3s Addon Controller 定期重置 CoreDNS ConfigMap，直接 `kubectl edit` 修改无效。

**修复**：使用 `coredns-custom` ConfigMap 持久化配置：
- 将 `coredns-custom.yaml` 放入 `/var/lib/rancher/k3s/server/manifests/`
- K3s 每次启动自动 apply，永久生效
- 参考 `references/conf/coredns-custom.yaml.tpl`（通过 envsubst 渲染）

---

## 3. Traefik 内部端口权限问题

**现象**：Traefik Pod 报错权限不足，无法监听端口。

**根因**：Traefik 以非 root 用户运行，容器内端口必须 >= 1024。

**修复**：
- 容器内使用 8000（web）/ 8443（websecure），映射到宿主机 8083 / 8443
- 不使用 hostPort，由 K3s svclb 自动处理

---

## 4. CoreDNS Pod 一直处于 ContainerCreating

**现象**：安装完成后 CoreDNS Pod 长时间无法启动。

**根因**：国内网络无法拉取 `registry.k8s.io/coredns` 镜像。

**修复**：在 `registries.yaml` 中配置 `docker.io` 和 `registry.k8s.io` 镜像加速：
```yaml
mirrors:
  docker.io:
    endpoint:
      - "https://docker.1ms.run"
      - "https://docker.m.daocloud.io"
```
重启 K3s 后等待镜像拉取完成（最多 5 分钟）。

---

## 5. 单机部署 Traefik 端口冲突

**现象**：K3s 内置 Traefik 占用 :80，与 infra-nginx 冲突。

**根因**：单机部署时 infra-nginx 已占用 :80。

**修复**：安装时通过 `--disable traefik` 禁用内置 Traefik，再通过 HelmChart 安装自定义 Traefik，使用 8083 端口（见 `references/traefik-values.yaml`）。

---

## 6. kubectl/jq 在 CI 容器中无法运行（K3s symlink 问题）

**现象**：CI Job 中 `kubectl` 执行成功但输出异常，`jq` 报动态链接错误。

**根因**：
- K3s 机器上 `/usr/local/bin/kubectl` 是 k3s 二进制符号链接，挂载进 Debian CI 容器后行为异常
- yum 安装的 jq 依赖 `libjq.so.1`，不同 Linux 发行版无法共用

**修复**：由 `setup-gitlab-runner start` 自动下载静态二进制（kubectl-bin v1.32.0、jq-static 1.7.1）存入 `/opt/tech-stack/cicd/`，单独 bind-mount 到容器内 PATH。
