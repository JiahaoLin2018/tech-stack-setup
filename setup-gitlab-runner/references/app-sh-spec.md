# app.sh 部署规范

> 本文档解释 `app.sh` 脚本从 Apollo 读取配置后生成的 K8s 资源结构，帮助开发者理解部署产出物。

---

## 一、脚本职责

`app.sh` 是 CI/CD Pipeline 的核心脚本，负责：

1. **读取 Apollo 配置**：从 `tech.common` namespace 获取 `ops.*` 配置项
2. **构建 Docker 镜像**：根据应用类型（Java/前端/Python）生成 Dockerfile 并构建
3. **推送镜像到 Harbor**：`harbor.renew.com/library/{appId}:{commitSha}`
4. **部署到 K3s**：动态生成并 apply K8s 资源

---

## 二、执行流程

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        app.sh 执行流程                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. 检测应用类型（pom.xml → Java / package.json → 前端 / requirements.txt → Python）
│     │
│     ▼
│  2. 从 Apollo 读取 tech.common 配置
│     │  URL: http://apollo-config-{env}.renew.com/configs/{appId}/default/tech.common
│     ▼
│  3. 确保 K8s namespace 和 harbor-registry Secret 存在
│     │
│     ▼
│  4. 构建镜像（如启用 autoReuseImage 且镜像已存在则跳过）
│     │
│     ▼
│  5. 依次创建 K8s 资源：
│     ├─ PVC（如果 persistentStorage=true）
│     ├─ Deployment
│     ├─ HPA（如果配置了 k8sReplicasMin/Max）
│     ├─ PDB（多副本自动创建）
│     ├─ Service（始终创建）
│     └─ Ingress（如果配置了 appDomain）
│     │
│     ▼
│  6. 等待 Deployment rollout 完成（超时 4 分钟）
│     │
│     ▼
│  7. 发送钉钉通知（如果配置了 DINGTALK_WEBHOOK）
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 三、生成的 K8s 资源

### 3.1 Deployment

**Java 应用**：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {appId}
  namespace: {env}
  labels:
    app: {appId}
spec:
  replicas: {ops.k8sReplicas}
  strategy:
    type: RollingUpdate  # 或 Recreate（由 ops.k8sUpdateStrategy 决定）
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: {appId}
  template:
    metadata:
      labels:
        app: {appId}
        version: {随机值}  # 强制滚动更新
    spec:
      terminationGracePeriodSeconds: 180
      containers:
      - name: {appId}
        image: harbor.renew.com/library/{appId}:{commitSha}
        imagePullPolicy: Always
        ports:
        - containerPort: {ops.appPort 或 server.port}
        env:
        - name: JAVA_OPTS
          # bridge 模式：{ops.javaCmdOptions} -Xmx{内存}m -Xms{内存}m -Dapp.id={appId} -Dapollo.meta=http://apollo-config-{env}.renew.com
          # agent 模式：上述 + " -javaagent:/opt/otel/opentelemetry-javaagent.jar"
          value: "{ops.javaCmdOptions} -Xmx{内存}m -Xms{内存}m -Dapp.id={appId} -Dapollo.meta=http://apollo-config-{env}.renew.com"
        - name: SPRING_PROFILES_ACTIVE
          value: "{env}"
        # ========= OTel 环境变量（仅当 ops.supportOtel=true 时注入） =========
        - name: OTEL_SERVICE_NAME
          value: "{appId}"
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "http://otel-{domainEnv}.renew.com:4317"  # domainEnv: prod→prod；dev/sit/fat/uat→nonprod
        - name: OTEL_EXPORTER_OTLP_PROTOCOL
          value: "grpc"
        - name: OTEL_RESOURCE_ATTRIBUTES
          value: "deployment.environment={env},service.namespace={env}"  # 关键：env 标签注入，用于 Logs/Traces 环境隔离
        - name: OTEL_METRICS_EXPORTER
          value: "none"  # Metrics 由 Prometheus 拉取 /actuator/prometheus，不走 OTLP
        - name: OTEL_LOGS_EXPORTER
          value: "otlp"
        - name: OTEL_TRACES_EXPORTER
          value: "otlp"
        # 仅 agent 模式额外注入：避免 Agent 读取 Actuator 并重复导出指标
        - name: OTEL_INSTRUMENTATION_MICROMETER_ENABLED
          value: "false"
        # ========= /OTel 环境变量 =========
        resources:
          requests:
            cpu: "100m"
            memory: "{containerMinMemory}Mi"  # appMemoryLimit / 2
          limits:
            cpu: "{ops.appCpuLimit}"
            memory: "{containerMaxMemory}Mi"  # appMemoryLimit * 2
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "sleep 5 && curl -X PUT http://consul-{env}.renew.com:8500/v1/agent/service/deregister/{appId}"]
        livenessProbe:
          httpGet:
            path: {ops.appHealthUri}
            port: {appPort}
          initialDelaySeconds: 30
          periodSeconds: 10
          failureThreshold: 18
        readinessProbe:
          httpGet:
            path: {ops.appHealthUri}
            port: {appPort}
          initialDelaySeconds: 10
          periodSeconds: 5
          failureThreshold: 18
        volumeMounts:  # 如果 persistentStorage=true
        - name: data-volume
          mountPath: {ops.persistentStoragePath}
      volumes:  # 如果 persistentStorage=true
      - name: data-volume
        persistentVolumeClaim:
          claimName: data-volume-{appId}
      imagePullSecrets:
      - name: harbor-registry
```

**前端应用**：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {appId}
  namespace: {env}
spec:
  replicas: {ops.k8sReplicas}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    spec:
      terminationGracePeriodSeconds: 60
      containers:
      - name: {appId}
        image: harbor.renew.com/library/{appId}:{commitSha}
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: "10m"
            memory: "32Mi"
          limits:
            cpu: "{ops.appCpuLimit}"
            memory: "{ops.appMemoryLimit}Mi"
        livenessProbe:
          httpGet:
            path: /
            port: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
      imagePullSecrets:
      - name: harbor-registry
```

**Python 应用**：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {appId}
  namespace: {env}
spec:
  replicas: {ops.k8sReplicas}
  template:
    spec:
      terminationGracePeriodSeconds: 60
      containers:
      - name: {appId}
        image: harbor.renew.com/library/{appId}:{commitSha}
        command: ["/bin/sh", "-c", "{ops.pyStartCommand}"]
        ports:
        - containerPort: {ops.appPort}  # Python 必须显式配置
        env:
        - name: RUN_ENV
          value: "{env}"
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
          limits:
            cpu: "{ops.appCpuLimit}"
            memory: "{ops.appMemoryLimit}Mi"
        livenessProbe:
          httpGet:
            path: {ops.appHealthUri}
            port: {ops.appPort}
        readinessProbe:
          httpGet:
            path: {ops.appHealthUri}
            port: {ops.appPort}
      imagePullSecrets:
      - name: harbor-registry
```

---

### 3.2 HPA（HorizontalPodAutoscaler）

**创建条件**：同时配置 `ops.k8sReplicasMin` 和 `ops.k8sReplicasMax`

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {appId}-hpa
  namespace: {env}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {appId}
  minReplicas: {ops.k8sReplicasMin}
  maxReplicas: {ops.k8sReplicasMax}
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: {ops.k8sTargetCPU}
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: {ops.k8sTargetMemory}
```

---

### 3.3 PDB（PodDisruptionBudget）

**创建条件**：`ops.k8sReplicas >= 2` 且 `ops.k8sPdbMinAvailable != 0`

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {appId}-pdb
  namespace: {env}
spec:
  minAvailable: {ops.k8sPdbMinAvailable 或默认 1}
  selector:
    matchLabels:
      app: {appId}
```

**注意**：`minAvailable` 必须 < `replicas`，否则节点维护时 `kubectl drain` 会被永久阻塞。

---

### 3.4 Service

**创建条件**：始终创建

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {appId}
  namespace: {env}
spec:
  ports:
  - name: http
    protocol: TCP
    port: {appPort}
    targetPort: {appPort}
  selector:
    app: {appId}
```

---

### 3.5 Ingress

**创建条件**：配置了 `ops.appDomain`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {appId}  # 多域名时第二个为 {appId}-2，以此类推
  namespace: {env}
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  rules:
  - host: {ops.appDomain}
    http:
      paths:
      - path: {ops.appDomainReverseProxyUri}
        pathType: Prefix
        backend:
          service:
            name: {appId}
            port:
              number: {appPort}
```

---

### 3.6 PVC（PersistentVolumeClaim）

**创建条件**：`ops.persistentStorage=true`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-volume-{appId}
  namespace: {env}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: {ops.persistentStorageSize}Gi
```

---

## 四、Apollo 配置与 K8s 资源映射

| Apollo 配置项 | K8s 资源 | 说明 |
|--------------|---------|------|
| `ops.k8sReplicas` | Deployment.spec.replicas | 副本数 |
| `ops.k8sUpdateStrategy` | Deployment.spec.strategy.type | `RollingUpdate` / `Recreate` |
| `ops.appCpuLimit` | Deployment.spec.template.spec.containers[].resources.limits.cpu | CPU 限制 |
| `ops.appMemoryLimit` | Deployment.spec.template.spec.containers[].resources.limits.memory | 内存限制（实际为 ×2） |
| `ops.appDomain` | Ingress.spec.rules[].host | 域名，多个空格分隔 |
| `ops.appDomainReverseProxyUri` | Ingress.spec.rules[].http.paths[].path | 反向代理路径 |
| `ops.k8sReplicasMin` + `ops.k8sReplicasMax` | HPA | 同时配置才启用 |
| `ops.k8sTargetCPU` | HPA.spec.metrics[].resource.target.averageUtilization | CPU 扩缩阈值 |
| `ops.k8sTargetMemory` | HPA.spec.metrics[].resource.target.averageUtilization | 内存扩缩阈值 |
| `ops.k8sPdbMinAvailable` | PDB.spec.minAvailable | 多副本默认 1 |
| `ops.persistentStorage` | PVC | `true` 时创建 |
| `ops.persistentStorageSize` | PVC.spec.resources.requests.storage | 存储大小 |
| `ops.persistentStoragePath` | Deployment volumeMounts.mountPath | 挂载路径 |
| `ops.javaVersion` | 基础镜像 + OTel 模式约束 | `harbor.renew.com/library/jdk:{version}`；`< 17` 时 app.sh 强制 `ops.otelMode=agent`（Micrometer Tracing 1.4.x 需 JDK 17+） |
| `ops.pythonVersion` | 基础镜像 | `harbor.renew.com/library/python:{version}` |
| `ops.appHealthUri` | livenessProbe/readinessProbe httpGet.path | 健康检查路径 |
| `ops.appPort` | containerPort | 应用端口 |
| `ops.supportOtel` | OTel env 块 + JAVA_OPTS | `true` 注入完整 OTEL_* 环境变量；`false` 全部不注入（Metrics 仍由 Prometheus 拉取） |
| `ops.otelMode` | JAVA_OPTS / OTel env 增量 | `bridge`（SB 3.x 主力，无 javaagent）/ `agent`（SB 2.x 兜底，加 `-javaagent:/opt/otel/opentelemetry-javaagent.jar` + `OTEL_INSTRUMENTATION_MICROMETER_ENABLED=false`） |

---

## 五、镜像命名规则

| 配置项 | 值 | 说明 |
|-------|-----|------|
| 镜像仓库 | `harbor.renew.com/library` | 固定 |
| 镜像名称 | `{appId}` | 与 Apollo AppId 一致 |
| 镜像标签 | `{CI_COMMIT_SHA 前 8 位}` | 如 `a1b2c3d4` |
| 完整镜像 | `harbor.renew.com/library/order-service:a1b2c3d4` | 示例 |

---

## 六、环境变量注入

### Java 应用

#### 始终注入

| 环境变量 | 来源 | 说明 |
|---------|------|------|
| `JAVA_OPTS` | 脚本拼接 | JVM 参数、堆大小、Apollo Meta、Agent 模式额外含 `-javaagent` |
| `SPRING_PROFILES_ACTIVE` | `{env}` | 当前部署环境 |

#### 仅当 `ops.supportOtel=true` 注入（双方案共用）

| 环境变量 | 值 | 说明 |
|---------|-----|------|
| `OTEL_SERVICE_NAME` | `{appId}` | 链路追踪服务名 |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://otel-{domainEnv}.renew.com:4317` | domainEnv: `dev/sit/fat/uat` → `nonprod`；`prod` → `prod` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc` | OTLP 传输协议 |
| `OTEL_RESOURCE_ATTRIBUTES` | `deployment.environment={env},service.namespace={env}` | env 标签注入（Logs/Traces 环境隔离的关键） |
| `OTEL_METRICS_EXPORTER` | `none` | Metrics 走 Prometheus 拉取，不走 OTLP（避免与 Actuator 重复） |
| `OTEL_LOGS_EXPORTER` | `otlp` | 日志经 OTLP 推送到 OTel Collector |
| `OTEL_TRACES_EXPORTER` | `otlp` | 链路经 OTLP 推送到 OTel Collector |

#### 仅当 `ops.otelMode=agent` 额外注入

| 环境变量 | 值 | 说明 |
|---------|-----|------|
| `OTEL_INSTRUMENTATION_MICROMETER_ENABLED` | `false` | 关闭 Agent 的 Micrometer Bridge，避免重复导出指标 |
| JAVA_OPTS `-javaagent` | `/opt/otel/opentelemetry-javaagent.jar` | OTel Java Agent v2.26.1，由 setup-gitlab-runner 统一管理（宿主机 `/opt/tech-stack/cicd/`，volumes 挂载到 `/opt/otel/`） |

### Python 应用

| 环境变量 | 来源 | 说明 |
|---------|------|------|
| `RUN_ENV` | `{env}` | 当前部署环境 |

---

## 七、健康检查配置

| 应用类型 | livenessProbe | readinessProbe | 超时时间 |
|---------|---------------|----------------|---------|
| Java | `ops.appHealthUri`（默认 `/actuator/health`） | 同左 | initialDelay: 30s/10s |
| 前端 | `/` | `/` | initialDelay: 5s |
| Python | `ops.appHealthUri` | 同左 | initialDelay: 10s |

---

## 八、生产环境权限控制

`app.sh` 内置生产环境部署白名单（仅 `prod` 环境生效）：

```bash
# 硬编码授权用户列表
userList="root admin devops jiahao.lin"
```

非白名单用户触发生产部署时，Pipeline 会直接失败并提示权限不足。

---

## 九、钉钉通知

**触发时机**：部署开始、成功、失败

**配置方式**：在 `.gitlab-ci.yml` 中设置 `DINGTALK_WEBHOOK` 变量

**通知内容**：
- 项目名称、部署环境
- 分支/标签、耗时
- 操作人、状态（成功/失败）

---

## 十、排障命令

```bash
# 查看 Deployment 状态
kubectl get deployment {appId} -n {env}

# 查看 Pod 状态
kubectl get pods -n {env} -l app={appId}

# 查看 Pod 日志
kubectl logs -f deployment/{appId} -n {env}

# 查看 Pod 详情（排查 ImagePullBackOff 等）
kubectl describe pod {podName} -n {env}

# 查看 Ingress
kubectl get ingress -n {env}

# 查看 HPA 状态
kubectl get hpa {appId}-hpa -n {env}

# 查看 PDB 状态
kubectl get pdb {appId}-pdb -n {env}

# 手动扩缩容
kubectl scale deployment/{appId} --replicas=3 -n {env}

# 强制重启 Pod
kubectl rollout restart deployment/{appId} -n {env}

# 回滚到上一版本
kubectl rollout undo deployment/{appId} -n {env}
```
