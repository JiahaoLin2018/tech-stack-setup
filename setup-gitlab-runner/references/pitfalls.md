# setup-gitlab-runner 运维记录

> 部署、注册、CI Pipeline 执行过程中遇到的常见问题与处理方法。actions/ 流程已对应修复，本文件作为排障速查与设计原因说明。

## 1. Docker socket 权限问题

**现象**：CI 作业执行 `docker build` 报错 `permission denied`。

**根因**：宿主机 `/var/run/docker.sock` 权限为 `root:root 660`，Runner 容器内用户无权限。

**处理**：
```bash
# 方案一：将 runner 用户加入 docker 组（需重建容器）
docker exec tech-gitlab-runner-nonprod usermod -aG docker gitlab-runner

# 方案二：临时放宽权限（生产环境不推荐）
chmod 666 /var/run/docker.sock
```

---

## 2. Runner 容器内无法解析 gitlab.renew.com

**现象**：`register` 时报错 `dial tcp: connection refused`。

**根因**：Runner 容器内 DNS 未指向 dnsmasq，无法解析 `*.renew.com`。

**处理**：确认目标机器已配置 DNS 指向 dnsmasq：
```bash
cat /etc/resolv.conf | grep nameserver
# 应指向 dnsmasq 服务器 IP
```

或注册时加 `--docker-add-host "gitlab.renew.com:<gitlab-ip>"` 临时绕过。

---

## 3. CI Job 中 kubectl/jq 找不到或行为异常

**现象**：CI 作业报 `kubectl: not found` 或 jq 动态链接错误。

**根因**：
- K3s 机器上 `/usr/local/bin/kubectl` 是 k3s symlink，挂载进 CI 容器实际指向 k3s 二进制（75MB），其逻辑依赖 `/var/lib/rancher/k3s/` 宿主机路径，在容器内无法作为 kubectl 使用
- yum/apt 安装的 jq 依赖 `libjq.so.1`、`libonig.so.5`，跨 Linux 发行版（CentOS → Debian）挂载时动态链接器找不到 so 文件

**处理**：使用静态二进制（由 `start` 步骤 5 自动下载到 `/opt/tech-stack/cicd/`），通过 config.toml volumes 单独 bind-mount 到 CI 容器 `/usr/local/bin/`：

```toml
volumes = [
  "/opt/tech-stack/cicd/kubectl-bin:/usr/local/bin/kubectl:ro",
  "/opt/tech-stack/cicd/jq-static:/usr/local/bin/jq:ro",
  "/opt/tech-stack/cicd/docker-static:/usr/local/bin/docker:ro"
]
```

验证（在实际 CI 镜像中）：
```bash
docker run --rm \
  -v /opt/tech-stack/cicd/kubectl-bin:/usr/local/bin/kubectl:ro \
  -v /opt/tech-stack/cicd/jq-static:/usr/local/bin/jq:ro \
  maven:3.9-eclipse-temurin-21 bash -c \
  "kubectl version --client && jq --version && echo TOOLS_OK"
```

---

## 4. Runner 18.x 注册参数限制

**现象**：`register` 报错 `Runner configuration other than name and executor configuration is reserved`。

**根因**：Runner 18.x 使用 glrt- token 时，`--locked`、`--run-untagged`、`--tag-list` 等参数已从 `register` 命令移除。

**处理**：register 只保留 executor 相关参数。tag（`non-prod` / `prod`）和运行策略在 GitLab UI 中配置：
Settings → CI/CD → Runners → 编辑 Runner

---

## 5. `--env` 参数语义区分（B 类契约）

**背景**：`--env` 在本 skill 中有两种含义，须严格区分：

| 参数 | 含义 | 允许值 |
|------|------|--------|
| `setup-gitlab-runner --env` | **集群类型**（B 类契约） | `nonprod` / `prod` |
| `app.sh --env`（CI 内部） | **业务部署环境** | `dev` / `sit` / `fat` / `uat` / `prod` |

`setup-gitlab-runner --env nonprod` 部署的 Runner 可以执行 dev/sit/fat/uat 任意环境的部署（通过 app.sh 内部 `--env` 区分）。

---

## 6. 配置修改后 config.toml 不自动更新

**现象**：修改 `.env` 后重建容器，Runner 配置未变化。

**根因**：`config.toml` 是独立文件，不随 `.env` 变更自动更新。

**处理**：修改配置后手动编辑或重新注册：
```bash
vi /opt/tech-stack/gitlab-runner/config/config.toml
cd /opt/tech-stack/gitlab-runner && docker compose restart
```

---

## 7. app.sh 中 Harbor 密码注入

**设计原因**：`app.sh` 需要使用 Harbor 密码登录推送镜像，但禁止把密码硬编码进文件提交 git。

**处理**：
1. `references/app.sh` 中 `HARBOR_PASSWORD` 字段使用 `CHANGE_ME_HARBOR_PASSWORD` 占位符
2. `actions/start.md` 步骤 6 从 skill 目录的 `.env` 读取实际密码，通过 `sed` 替换后再上传
3. `actions/verify.md` 同样前置读取密码用于 Harbor API 验证
4. 同样机制处理 `settings.xml` 的 `CHANGE_ME_NEXUS_PASSWORD`

---

## 8. 双方案 OTel 接入：ops.otelMode + ops.javaVersion 决策树

**背景**：app.sh 需要在 Pod 部署时决定使用 Bridge（SB 3.x 主力）还是 Java Agent（SB 2.x 兜底），并保证两套方案共用 Prometheus 指标通路、互不重复。

**关键约束**：
- `ops.javaVersion < 17` → app.sh 强制覆写 `ops.otelMode=agent`（Micrometer Tracing 1.4.x 需要 JDK 17+）
- 两种模式都注入 `OTEL_METRICS_EXPORTER=none`（Metrics 走 Prometheus consul_sd 拉取，避免与 Actuator 重复）
- agent 模式额外注入 `OTEL_INSTRUMENTATION_MICROMETER_ENABLED=false`（关闭 Agent 的 Micrometer Bridge，避免 Agent 读取 Actuator 二次导出）
- agent 模式 `JAVA_OPTS` 追加 `-javaagent:/opt/otel/opentelemetry-javaagent.jar`

**配置示例**（Apollo `tech.common`）：
```properties
ops.supportOtel = true
ops.otelMode = bridge    # Spring Boot 3.x（默认）
# 或
ops.otelMode = agent     # Spring Boot 2.x 兜底（JDK<17 自动覆写为此）
```

---

## 9. OTel Java Agent 由 setup-gitlab-runner 统一管理

**设计原因**：Agent 既不集成进基础镜像（每版本 JDK 都要重建镜像），也不放在业务镜像（无法跨服务复用）。统一存放到宿主机 CI/CD 共享目录通过 volumes 挂载，可：
- 跨 JDK 8~21 版本通用
- 更新只需替换一个文件，无需重建任何镜像
- 与 app.sh / settings.xml / kubectl-bin 管理方式一致

**实现**：`actions/start.md` 步骤 5.4 下载 OTel Java Agent v2.26.1 到 `/opt/tech-stack/cicd/opentelemetry-javaagent.jar`，由 `config.toml` volumes 挂载为容器内 `/opt/otel/opentelemetry-javaagent.jar:ro`。

**故障表现**：若 Agent 文件缺失，Agent 模式应用启动报 `Error opening zip file or JAR manifest missing : /opt/otel/opentelemetry-javaagent.jar`。重新执行 `start`（步骤 5.4 幂等下载）即可恢复。
