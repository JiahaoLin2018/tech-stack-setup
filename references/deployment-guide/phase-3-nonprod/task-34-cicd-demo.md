# Task 34 — CI/CD Demo 端到端验证

> 验证完整 Pipeline 链路（不部署任何远程基础设施）。对应 architecture-blueprint.md 第五部分阶段三 3-9 ~ 3-10。

## 前置条件

| 条件 | 说明 |
|------|------|
| 前置 task | task-06（Apollo nonprod，需导入 `tech.common`）+ task-33（Runner nonprod）+ 全部 nonprod 中间件 + LGT 栈 |
| Apollo 访问 | `apollo.renew.com` Portal 可登录 |

## 架构约束

- E 类业务接入指导，不接受 `--env`，action 为 `demo` / `integrate`
- 不部署任何远程基础设施
- 由本 task 验证 task-01~33 的整体链路是否通畅

## 步骤一：导入 Apollo `tech.common` 公共 namespace（首次部署必做）

将 `setup-cicd/references/apollo-tech-common.properties` 导入 Apollo `tech.common` 公共 namespace 并发布（默认对 dev / sit / fat / uat / pro 全部 5 个 Apollo 环境生效；`pro` 在 task-47 部署后接入）：

- 通用：K8s 副本数 / HPA / PDB / `ops.appCpuLimit=1` / `ops.appMemoryLimit=1024` 等默认资源限制
- Java：`ops.javaVersion=21` / `ops.supportOtel=true` / `ops.otelMode=bridge`（Spring Boot 3.x 主力）/ `ops.javaCmdOptions` JVM 参数
- 前端：`ops.nodejsVersion=20` / `ops.nodejsBuildCommand` / `ops.htmlPackageDirectory=dist`（运行时固定 nginx:1.27）
- Python：`ops.pythonVersion=3.11` / `ops.pyBuildCommand` / `ops.pyStartCommand`（项目 namespace 必须覆盖 `ops.appPort`）

## 步骤二：执行 Demo 推送

```bash
/setup-cicd demo
```

> 推送 demo-backend（Spring Boot 3.5 + JDK 21 + 方案 A Bridge）+ demo-frontend（Vue 3 + nginx）到固定 SSH 仓库 `demo/demo-backend` / `demo/demo-frontend`。

## 步骤三：触发 Pipeline 验证

1. 在 GitLab 中找到 demo 仓库 → Pipelines → 手动触发 `fat_deploy`
2. 等待 Runner 接收 Job，按阶段执行：编译 → 镜像 push → kubectl apply
3. 在 K3s `fat` Namespace 中查看 Pod / HPA / Ingress

## 验证标准

- [ ] Apollo `tech.common` 公共 namespace 已发布（dev / sit / fat / uat 4 个非生产环境就绪，pro 在 task-47 后生效）
- [ ] Pipeline 全阶段成功（jar / fat_deploy）
- [ ] `kubectl get pods -n fat` 显示 demo-backend / demo-frontend Pod Running
- [ ] HPA / PDB / Service / Ingress 资源已创建
- [ ] Pod 通过 `mysql-fat.renew.com` 等域名直连 FAT 中间件
- [ ] Pod 通过 `apollo-config-fat.renew.com` 拉取 Apollo 配置
- [ ] Grafana 中可见 demo Service 的指标 / 日志 / 链路（env=fat 标签）
- [ ] Consul 中可见 demo 服务注册（带 `metrics` tag）

## 故障排查

- Runner 接不到 Job：检查 `.gitlab-ci.yml` `tags: [non-prod]` 是否匹配
- 镜像推不到 Harbor：检查 Docker daemon.json `insecure-registries`
- Pod 无法拉取镜像：检查 K3s `registries.yaml` 是否含 `harbor.renew.com`
- Apollo 拉不到配置：检查 `apollo-config-{env}.renew.com` 反代是否生效

## 后续步骤

- 业务项目按 `setup-cicd integrate` 模板接入（详见 setup-cicd/actions/integrate.md）
- 任意时机可继续 task-35（edge-nginx nonprod，可选）或 task-36~48（生产建设）
