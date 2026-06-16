# setup-nexus

使用 Docker Compose 部署和管理 Nexus Repository OSS 3 Maven 私服，支持本地和远程服务器两种部署模式。

## 安装

```bash
bash install.sh
```

安装后即可在 Claude Code 中使用 `/setup-nexus` 命令。

## 前提条件

- 远程模式：SSH 可连接目标服务器；密码模式需本地安装 `sshpass`
- 目标服务器建议内存 8GB 以上

## 支持的命令

| 命令 | 说明 |
|------|------|
| `/setup-nexus start` | 启动 Nexus（含权限设置、健康等待最多 150 秒、初始密码获取） |
| `/setup-nexus stop` | 停止并移除容器 |
| `/setup-nexus status` | 查看容器状态、资源占用与数据目录大小 |
| `/setup-nexus verify` | 验证 API 可达、获取初始密码、展示 Maven 配置示例 |
| `/setup-nexus logs` | 查看容器日志（最近 50 行） |

## 远程部署示例

```bash
# 使用密码部署到远程服务器
/setup-nexus start --host <HOST> --user deploy --password mypassword

# 使用 SSH 密钥部署
/setup-nexus start --host <HOST> --key ~/.ssh/id_rsa

# 自定义 SSH 端口
/setup-nexus start --host <HOST> --key ~/.ssh/id_rsa --ssh-port 2222

# 查看远程服务状态
/setup-nexus status --host <HOST> --key ~/.ssh/id_rsa
```

## .env 配置说明

工作目录`/opt/tech-stack/nexus/`中的 `.env` 文件：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `NEXUS_HOSTNAME` | `nexus.renew.com` | 容器主机名（dnsmasq 域名解析） |
| `NEXUS_PORT` | `8081` | UI 与 Maven HTTP API 端口 |
| `NEXUS_DOCKER_PORT` | `8082` | Docker Registry 端口（需在 Nexus 中配置） |
| `NEXUS_JVM_MIN_HEAP` | `1g` | JVM 最小堆内存 |
| `NEXUS_JVM_MAX_HEAP` | `2g` | JVM 最大堆内存 |
| `NEXUS_DIRECT_MEMORY` | `2g` | JVM 直接内存（Direct Memory） |

## Maven 集成配置

首次登录修改密码后，在 `~/.m2/settings.xml` 中添加：

```xml
<settings>
  <mirrors>
    <mirror>
      <id>nexus</id>
      <mirrorOf>*</mirrorOf>
      <url>http://nexus.renew.com/repository/maven-public/</url>
    </mirror>
  </mirrors>
  <servers>
    <server>
      <id>nexus</id>
      <username>admin</username>
      <password>YOUR_PASSWORD</password>
    </server>
    <server>
      <id>nexus-releases</id>
      <username>admin</username>
      <password>YOUR_PASSWORD</password>
    </server>
    <server>
      <id>nexus-snapshots</id>
      <username>admin</username>
      <password>YOUR_PASSWORD</password>
    </server>
  </servers>
</settings>
```

项目 `pom.xml` 分发配置：

```xml
<distributionManagement>
  <repository>
    <id>nexus-releases</id>
    <url>http://nexus.renew.com/repository/maven-releases/</url>
  </repository>
  <snapshotRepository>
    <id>nexus-snapshots</id>
    <url>http://nexus.renew.com/repository/maven-snapshots/</url>
  </snapshotRepository>
</distributionManagement>
```

## 目录结构

```
setup-nexus/
├── SKILL.md                      # AI 执行指令
├── README.md                     # 入门指引（人类读取）
├── install.sh                    # 安装脚本
├── actions/
│   ├── start.md                  # 启动流程（本地+远程，含权限设置和健康等待）
│   ├── stop.md
│   ├── status.md
│   ├── verify.md                 # 含初始密码获取与 Maven 配置示例
│   └── logs.md
└── references/
    ├── docker-compose.yml        # 生产级配置（JVM 参数、资源限制、健康检查）
    ├── .env.example              # 环境变量模板
    └── pitfalls.md               # 踩坑记录
```

## 注意事项

- Nexus 容器以 uid=200 运行，数据目录需要 `chmod 755` 权限
- 首次登录后 Nexus 自动删除 `admin.password` 文件，之后使用自定义密码
- Nexus 内存占用较大（约 1.5-3GB），请确保 Docker 有足够内存分配
- 制品数据持久化在 `data/` 目录中，重启后完全恢复
