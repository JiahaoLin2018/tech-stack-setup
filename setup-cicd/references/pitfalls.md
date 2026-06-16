# setup-cicd 运维记录

> 业务接入 CI/CD（demo 端到端验证 / integrate 接入指南）过程中遇到的常见问题与处理方法。app.sh / settings.xml / Runner 相关运维记录归 `setup-gitlab-runner/references/pitfalls.md`。

## 1. Apollo `tech.common` 公共 namespace 未导入或未关联

**现象**：CI Job 报错 `[ERROR] 无法从 Apollo 获取配置`、`ops.imageDomain 未配置`，或 Pipeline 在 fat_deploy 阶段立即失败。

**根因**：业务项目对应的 AppId 在 Apollo Portal 未关联公共 namespace `tech.common`，或 `tech.common` namespace 本身未创建并发布。

**处理**：
1. 登录 Apollo Portal（`http://apollo.renew.com`）→ 管理员工具 → 命名空间管理 → 确认 `tech.common` 已创建并发布
2. 若未导入：把 `references/apollo-tech-common.properties` 全部内容粘贴到 `tech.common` 文本编辑器 → 发布
3. 业务应用：应用管理 → 找到对应 AppId → Namespace 管理 → 关联公共 namespace → `tech.common`
4. 在项目自身 namespace 中按 README.md 示例覆盖 `ops.appDomain` 等需要定制的项

---

## 2. Pipeline 触发了错误的 Runner

**现象**：dev/sit/fat/uat Pipeline 被 prod Runner 执行，或反之；Pipeline 一直 pending。

**根因**：`.gitlab-ci.yml` 中 `tags` 配置错误，或 Runner 在 GitLab UI 中 tag 设置错误。

**处理**：
- 非生产部署 job 必须 `tags: [non-prod]`，生产部署 job 必须 `tags: [prod]`（参考 `references/.gitlab-ci.yml` 模板）
- 在 GitLab UI → Settings → CI/CD → Runners → 编辑 Runner → 检查 tag 是否分别为 `non-prod` / `prod`
- 若 Pipeline 一直 pending，确认 GitLab UI 中 Runner 的 "Run untagged jobs" 选项以及 Runner 状态为 active

---

## 3. setup-cicd / app.sh / setup-gitlab-runner 的 `--env` 语义区分

**说明**：三处 `--env` 含义完全不同，配置时不要混淆：

| 参数 | 类别 | 含义 | 允许值 |
|------|-----|------|--------|
| `setup-cicd` | E 类（接入指导） | 不接受 `--env` | — |
| `setup-gitlab-runner --env` | B 类（域级共用+生产独立） | 集群类型 | `nonprod` / `prod` |
| `app.sh --env`（CI 内部，由 `.gitlab-ci.yml` `environment.name` 透传） | 业务部署环境 | `dev` / `sit` / `fat` / `uat` / `prod` |

setup-cicd 收到 `--env` 时告知用户后继续执行，部署环境最终由 Pipeline 内部 `app.sh` 根据 `CI_ENVIRONMENT_NAME` 决定。

---

## 4. Demo 验证失败：infra-nginx 无法路由非生产业务流量

**现象**：Demo 项目部署成功，访问 `demo.fat.web.renew.com` 返回 502 / 404。

**根因**：infra-nginx 的 `50-k3s-business.conf` 未配置或 `K3S_NONPROD_TRAEFIK_HOST` / `K3S_PROD_TRAEFIK_HOST` 变量指向错误。

**处理**：
1. 确认 setup-infra-nginx `.env` 中 `K3S_NONPROD_TRAEFIK_HOST` 指向非生产 K3s 节点（域名应为 `k3s-nonprod.renew.com`）
2. 直接走 K3s 验证：`curl -H "Host: demo.fat.web.renew.com" http://k3s-nonprod.renew.com:8083/`
3. 走 infra-nginx 验证：`curl -H "Host: demo.fat.web.renew.com" http://<INFRA_NGINX_IP>/`
4. 非生产业务流量路径：`用户 → infra-nginx :80 → K3s Traefik :8083 → Pod`（无 edge-nginx）

---

## 5. Harbor 镜像推送失败 / ImagePullBackOff

**现象**：CI Job 报错 `unauthorized: access to the requested resource is not authorized` 或 Pod `ImagePullBackOff`。

**根因**：业务项目无需在 GitLab CI/CD Variables 中配置 Harbor 凭据——`HARBOR_PASSWORD` 由 `setup-gitlab-runner start` 在部署 Runner 时通过 sed 替换注入到宿主机 `/opt/tech-stack/cicd/app.sh`，CI Job 容器挂载该脚本即可使用。常见根因是 setup-gitlab-runner 部署时 `.env` 中 `HARBOR_PASSWORD` 未配置真实值，或 K3s namespace 内的 `harbor-registry` Secret 未创建。

**处理**：
1. 检查 app.sh 是否包含真实密码：`grep 'HARBOR_PASSWORD=' /opt/tech-stack/cicd/app.sh | head -1`，输出不应包含 `CHANGE_ME_`
2. 若仍是占位符：编辑 `setup-gitlab-runner/references/.env` 设置 `HARBOR_PASSWORD=<实际密码>`，重跑 `/setup-gitlab-runner start --host <RUNNER_HOST>`
3. 检查目标 namespace 的 Harbor Secret：`kubectl get secret harbor-registry -n fat`；若不存在，由 app.sh 在首次 Pipeline 运行时自动创建（幂等）
4. Harbor 地址必须使用域名 `harbor.renew.com`（无端口，走 infra-nginx）；K3s `registries.yaml` 必须显式声明 `harbor.renew.com` 走 HTTP（K3s 默认 HTTPS 443 不通）
