#!/bin/bash
#===============================================================================
# Tech Stack Setup — CI/CD 部署脚本
#
# 用途：从 Apollo 读取配置，构建镜像，部署到 K3s
# 适配：Spring Boot 3.5 + Spring Cloud 2025 + JDK 21
#
# CI/CD Pipeline 设计：
#   Stage 1 (jar): Maven 编译 → 产物缓存到 GitLab Cache
#   Stage 2 (deploy): 从 cache 恢复 jar → 构建镜像 → 部署到 K3s
#
# 与原 app.sh 的差异：
#   - 镜像仓库：阿里云 ACR → Harbor
#   - 服务发现：Consul 独立集群 → Consul 容器化（Sidecar 模式可选）
#   - 链路追踪：Pinpoint → OTel + Tempo
#   - 日志采集：Filebeat → OTel Collector + Loki
#   - 存储：阿里云 NAS → Local PV / NFS
#
# GitLab CI 变量（最新版本）：
#   - CI_COMMIT_REF_NAME: 当前分支或 tag 名称
#   - CI_COMMIT_SHA: 当前 commit 完整 SHA
#   - CI_COMMIT_SHORT_SHA: commit SHA 前 8 位
#   - CI_ENVIRONMENT_NAME: 部署环境名称
#   - CI_PROJECT_NAME: 项目名称
#   - CI_PROJECT_DIR: 项目目录
#   - GITLAB_USER_LOGIN: 触发用户
#===============================================================================

set -eo pipefail

# 用途：获取当前脚本执行前的时间
startTime=$(date +%Y%m%d-%H:%M:%S)
startTime_s=$(date +%s)

#===============================================================================
# 配置区 — 根据实际环境修改
#===============================================================================
# Apollo 上云模式标志（仅生产生效）
# - false（默认/未上云）: apollo.meta=http://apollo-config-prod.renew.com         (内网 infra-nginx :80 反代到 :8605)
# - true（生产已上云）  : apollo.meta=http://apollo-config-prod.renew.com:8605    (PrivateZone 直连，必须带端口)
# 上云后由 setup-gitlab-runner actions/start.md 自动替换为 true，或手动编辑此文件
# 详见 cloud-migration-reference.md §4.1
APOLLO_CLOUD_MIGRATED="false"

# 镜像仓库
HARBOR_URL="harbor.renew.com"
HARBOR_PROJECT="library"
# ⚠️ Harbor 密码必须替换为实际密码！
# 部署前由 setup-gitlab-runner actions/start.md 步骤 6 自动替换，或手动编辑此文件
# 密码来源：env/harbor.md 或 Harbor 管理员
HARBOR_PASSWORD="CHANGE_ME_HARBOR_PASSWORD"

# K3s kubeconfig（CI Runner 挂载到此固定路径）
KUBECONFIG="/opt/tech-stack/cicd/kubeconfig"

#===============================================================================
# 工具检测函数
#===============================================================================

# 用途：检测 kubectl 是否可用
function checkKubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo "[ERROR] kubectl 未找到。请确认 Runner config.toml volumes 中包含静态 kubectl-bin 挂载："
        echo "[HINT]   /opt/tech-stack/cicd/kubectl-bin:/usr/local/bin/kubectl:ro"
        exit 1
    fi
    echo "[INFO] kubectl 版本: $(kubectl version --client --short 2>/dev/null || kubectl version --client | head -1)"
}

# 用途：检测 jq 是否可用
function checkJq() {
    if ! command -v jq &> /dev/null; then
        echo "[ERROR] jq 未找到。请确认 Runner config.toml volumes 中包含静态 jq-static 挂载："
        echo "[HINT]   /opt/tech-stack/cicd/jq-static:/usr/local/bin/jq:ro"
        exit 1
    fi
    echo "[INFO] jq 版本: $(jq --version)"
}

# 用途：登录 Harbor 镜像仓库
function loginHarbor() {
    echo "[INFO] 登录 Harbor: ${HARBOR_URL}"
    echo "${HARBOR_PASSWORD}" | docker login -u admin --password-stdin "${HARBOR_URL}"

    if [ $? -ne 0 ]; then
        echo "[ERROR] Harbor 登录失败"
        exit 1
    fi
}

# 用途：创建 K3s namespace 和 Harbor 密钥
function ensureK8sNamespace() {
    # 创建 namespace（如不存在）
    kubectl --kubeconfig="${KUBECONFIG}" get namespace "${currentEnv}" 2>/dev/null || \
        kubectl --kubeconfig="${KUBECONFIG}" create namespace "${currentEnv}"

    # 创建/更新 Harbor 镜像拉取密钥
    kubectl --kubeconfig="${KUBECONFIG}" create secret docker-registry harbor-registry \
        --docker-server="${HARBOR_URL}" \
        --docker-username=admin \
        --docker-password="${HARBOR_PASSWORD}" \
        -n "${currentEnv}" --dry-run=client -o yaml | \
        kubectl --kubeconfig="${KUBECONFIG}" apply -f -
}

#===============================================================================
# 执行环境准备
#===============================================================================
checkKubectl
checkJq
loginHarbor

#===============================================================================
# 函数定义
#===============================================================================

# 用途：生产环境部署权限校验（硬编码白名单）
function checkDeployPermission() {
    # 仅对生产环境校验（环境名包含 prod）
    if ! echo "${currentEnv}" | grep -qi "prod"; then
        return 0
    fi

    # 硬编码授权用户列表（生产环境部署权限）
    local userList="root admin devops jiahao.lin"

    # 检查当前用户是否在白名单中
    if echo " ${userList} " | grep -q " ${GITLAB_USER_LOGIN} "; then
        echo "[INFO] 生产环境部署：用户 ${GITLAB_USER_LOGIN} 已授权"
    else
        echo "[ERROR] 生产环境部署权限不足"
        echo "[ERROR] 当前用户: ${GITLAB_USER_LOGIN}"
        echo "[ERROR] 授权用户列表: ${userList}"
        echo "[HINT] 请联系运维添加部署权限"
        exit 1
    fi
}

# 用途：获取当前项目的应用类型
function getAppType() {
    if [ -f pom.xml ]; then
        appType='java'
    elif [ -f package.json ]; then
        appType='html'
    elif [ -f requirements.txt ]; then
        appType='python'
    else
        echo '[ERROR] 未知项目类型'
        exit 1
    fi
}

# 用途：获取公共的环境变量
function getCommonEnv() {
    # 环境变量校验
    if [ -z "${CI_ENVIRONMENT_NAME}" ]; then
        echo "[ERROR] 未设置应用部署到哪个环境，请确保 CI_ENVIRONMENT_NAME 环境变量已设置"
        exit 1
    fi

    if [ -z "${CI_COMMIT_SHA}" ]; then
        echo "[ERROR] 未设置 CI_COMMIT_SHA 环境变量"
        exit 1
    fi

    # 应用ID
    if [ -z "${APP_ID}" ]; then
        appId="${CI_PROJECT_NAME}"
        echo "[WARN] 未设置 APP_ID，使用项目名称: ${appId}"
    else
        appId="${APP_ID}"
    fi

    # 应用ID命名规范校验
    if ! echo "${appId}" | grep -qE '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$'; then
        echo "[ERROR] 应用ID \"${appId}\" 不符合规范。它只能由小写字母、数字、短横线(-)组成，并以小写字母或数字开始和结尾。"
        exit 1
    fi

    # 应用所在子目录
    if [ -z "${APP_SUB_DIR}" ]; then
        appSubDir="."
    else
        appSubDir="./${APP_SUB_DIR}"
    fi

    # 当前环境
    currentEnv="${CI_ENVIRONMENT_NAME}"

    # OTel Collector 域级区分 (非生产 vs 生产)
    if [[ "${currentEnv}" == "prod" ]]; then
        domainEnv="prod"
    else
        domainEnv="nonprod"
    fi

    # Apollo Config Service 地址（默认走 infra-nginx 反代；生产上云后追加端口 :8605 直连 PrivateZone）
    APOLLO_META="http://apollo-config-${currentEnv}.renew.com"
    if [[ "${currentEnv}" == "prod" ]] && [[ "${APOLLO_CLOUD_MIGRATED}" == "true" ]]; then
        APOLLO_META="${APOLLO_META}:8605"
    fi
    echo "[INFO] 环境: ${currentEnv}，Apollo Config: ${APOLLO_META}"

    # 镜像标签（使用 commit SHA 前 8 位）
    imageTag=$(echo "${CI_COMMIT_SHA}" | cut -b 1-8)

    # 强制更新的随机值
    notFixedValue="value-$(date +%Y%m%d%H%M%S)"

    # 从 Apollo 获取配置（connect-timeout: 5s，max-time: 15s，防止 Apollo 不可达时 Pipeline 长时间挂起）
    echo "[INFO] 从 Apollo 获取配置: ${APOLLO_META}/configs/${appId}/default/tech.common"
    commonConfig=$(curl -s --connect-timeout 5 --max-time 15 "${APOLLO_META}/configs/${appId}/default/tech.common" | jq -r '.configurations')

    if [ "${commonConfig}" = "null" ] || [ -z "${commonConfig}" ]; then
        echo "[ERROR] 无法从 Apollo 获取配置，请检查 appId 是否正确: ${appId}"
        exit 1
    fi

    # 解析 ops.* 配置（从 Apollo tech.common 获取，无默认值）
    # 配置来源：Apollo 公共 namespace tech.common，项目可覆盖
    appDomain=$(echo "${commonConfig}" | jq -r '.["ops.appDomain"] // empty')
    appDomainReverseProxyUri=$(echo "${commonConfig}" | jq -r '.["ops.appDomainReverseProxyUri"]')
    appCpuLimit=$(echo "${commonConfig}" | jq -r '.["ops.appCpuLimit"]')
    appMemoryLimit=$(echo "${commonConfig}" | jq -r '.["ops.appMemoryLimit"]')
    k8sReplicas=$(echo "${commonConfig}" | jq -r '.["ops.k8sReplicas"]')
    k8sUpdateStrategy=$(echo "${commonConfig}" | jq -r '.["ops.k8sUpdateStrategy"]')
    persistentStorage=$(echo "${commonConfig}" | jq -r '.["ops.persistentStorage"]')
    persistentStorageSize=$(echo "${commonConfig}" | jq -r '.["ops.persistentStorageSize"]')
    persistentStoragePath=$(echo "${commonConfig}" | jq -r '.["ops.persistentStoragePath"]')

    # HPA 配置（可选，不配置则不启用 HPA）
    k8sReplicasMin=$(echo "${commonConfig}" | jq -r '.["ops.k8sReplicasMin"] // empty')
    k8sReplicasMax=$(echo "${commonConfig}" | jq -r '.["ops.k8sReplicasMax"] // empty')
    k8sTargetCPU=$(echo "${commonConfig}" | jq -r '.["ops.k8sTargetCPU"]')
    k8sTargetMemory=$(echo "${commonConfig}" | jq -r '.["ops.k8sTargetMemory"]')

    # PDB 配置（多副本自动启用，单副本不启用）
    # - k8sReplicas >= 2 时，默认 minAvailable=1，可覆盖
    # - k8sReplicas = 1 时，不创建 PDB（单副本无法满足 minAvailable >= 1）
    k8sPdbMinAvailable=$(echo "${commonConfig}" | jq -r '.["ops.k8sPdbMinAvailable"] // ""')

    # 必填配置校验
    local missingConfigs=""

    if [ -z "${appDomainReverseProxyUri}" ] || [ "${appDomainReverseProxyUri}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.appDomainReverseProxyUri"
    fi
    if [ -z "${appCpuLimit}" ] || [ "${appCpuLimit}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.appCpuLimit"
    fi
    if [ -z "${appMemoryLimit}" ] || [ "${appMemoryLimit}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.appMemoryLimit"
    fi
    if [ -z "${k8sReplicas}" ] || [ "${k8sReplicas}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.k8sReplicas"
    fi
    if [ -z "${k8sUpdateStrategy}" ] || [ "${k8sUpdateStrategy}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.k8sUpdateStrategy"
    fi
    if [ -z "${persistentStorage}" ] || [ "${persistentStorage}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.persistentStorage"
    fi
    if [ -z "${persistentStorageSize}" ] || [ "${persistentStorageSize}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.persistentStorageSize"
    fi
    if [ -z "${persistentStoragePath}" ] || [ "${persistentStoragePath}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.persistentStoragePath"
    fi

    if [ -n "${missingConfigs}" ]; then
        echo "[ERROR] 缺少必要配置项:${missingConfigs}"
        echo "[HINT] 请在 Apollo tech.common namespace 或项目 namespace 中配置这些项"
        exit 1
    fi

    # k8sReplicas 正整数校验
    if ! echo "${k8sReplicas}" | grep -qE '^[1-9][0-9]*$'; then
        echo "[ERROR] 属性 ops.k8sReplicas 值应为正整数，当前值: ${k8sReplicas}"
        exit 1
    fi

    # CPU 值校验（支持正整数和任意位小数，如 0.5、0.10、1、2）
    # 注意：脚本内 Java/Python 的 requests.cpu 硬编码为 100m，ops.appCpuLimit 不应低于 0.2（200m）
    if ! echo "${appCpuLimit}" | grep -qE '^(0\.[0-9]*[1-9][0-9]*|[1-9][0-9]*(\.[0-9]+)?)$'; then
        echo "[ERROR] 属性 ops.appCpuLimit 值应为正数（如 0.5、1、2），当前值: ${appCpuLimit}"
        exit 1
    fi

    # 内存值校验
    # 注意：Python 应用的 requests.memory 硬编码为 256Mi，ops.appMemoryLimit 对 Python 不应低于 256
    if ! echo "${appMemoryLimit}" | grep -qE '^[1-9][0-9]*$'; then
        echo "[ERROR] 属性 ops.appMemoryLimit 值应为正整数，当前值: ${appMemoryLimit}"
        exit 1
    fi

    # 存储类（K3s 默认使用 local-path）
    k8sStorageClass='local-path'

    # 生产环境部署权限校验（硬编码白名单）
    checkDeployPermission

    echo "[INFO] 应用ID: ${appId}"
    echo "[INFO] 环境: ${currentEnv}"
    echo "[INFO] 副本数: ${k8sReplicas}"
    echo "[INFO] CPU限制: ${appCpuLimit}核"
    echo "[INFO] 内存限制: ${appMemoryLimit}Mi"
}

# 用途：获取 Java 应用专用的环境变量
function getJavaEnv() {
    # 从 Apollo 获取 Java 专用配置
    javaVersion=$(echo "${commonConfig}" | jq -r '.["ops.javaVersion"]')
    mavenBuildCommand=$(echo "${commonConfig}" | jq -r '.["ops.mavenBuildCommand"]')
    javaCmdOptions=$(echo "${commonConfig}" | jq -r '.["ops.javaCmdOptions"]')
    autoReuseImage=$(echo "${commonConfig}" | jq -r '.["ops.autoReuseImage"]')
    appHealthUri=$(echo "${commonConfig}" | jq -r '.["ops.appHealthUri"]')
    appPort=$(echo "${commonConfig}" | jq -r '.["ops.appPort"] // "null"')
    supportOtel=$(echo "${commonConfig}" | jq -r '.["ops.supportOtel"]')
    otelMode=$(echo "${commonConfig}" | jq -r '.["ops.otelMode"]')

    # 必填配置校验
    local missingConfigs=""

    if [ -z "${javaVersion}" ] || [ "${javaVersion}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.javaVersion"
    fi
    if [ -z "${mavenBuildCommand}" ] || [ "${mavenBuildCommand}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.mavenBuildCommand"
    fi
    if [ -z "${javaCmdOptions}" ] || [ "${javaCmdOptions}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.javaCmdOptions"
    fi
    if [ -z "${autoReuseImage}" ] || [ "${autoReuseImage}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.autoReuseImage"
    fi
    if [ -z "${appHealthUri}" ] || [ "${appHealthUri}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.appHealthUri"
    fi
    if [ -z "${supportOtel}" ] || [ "${supportOtel}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.supportOtel"
    fi

    if [ -n "${missingConfigs}" ]; then
        echo "[ERROR] 缺少 Java 配置项:${missingConfigs}"
        echo "[HINT] 请在 Apollo tech.common namespace 或项目 namespace 中配置这些项"
        exit 1
    fi

    # supportOtel 值校验
    if [ "${supportOtel}" != "true" ] && [ "${supportOtel}" != "false" ]; then
        echo "[ERROR] ops.supportOtel 值无效: ${supportOtel}，允许值: true | false"
        exit 1
    fi

    # 仅当 supportOtel=true 时检查 otelMode
    if [ "${supportOtel}" = "true" ]; then
        if [ -z "${otelMode}" ] || [ "${otelMode}" = "null" ]; then
            echo "[ERROR] 当 ops.supportOtel=true 时，必须配置 ops.otelMode（bridge | agent）"
            exit 1
        fi
        if [ "${otelMode}" != "bridge" ] && [ "${otelMode}" != "agent" ]; then
            echo "[ERROR] ops.otelMode 值无效: ${otelMode}，允许值: bridge | agent"
            exit 1
        fi
        # JDK < 17 强制使用 agent 模式（Micrometer Tracing 1.4.x 需要 JDK 17+）
        if [ "${javaVersion}" -lt 17 ] && [ "${otelMode}" = "bridge" ]; then
            echo "[WARN] JDK ${javaVersion} < 17，强制切换到 OTel Agent 模式"
            otelMode="agent"
        fi
    fi

    # Maven 版本
    mavenVersion='3.9'

    # 内存计算（容器内存 = JVM 内存 * 2，留给非堆内存）
    containerMaxMemory=$((appMemoryLimit * 2))
    containerMinMemory=$((appMemoryLimit / 2))
    jvmMaxMemory=${appMemoryLimit}
    jvmMinMemory=${containerMinMemory}

    # JDK 版本校验与运行时基础镜像选择
    #
    # 设计说明（编译 vs 运行时分离）：
    #   ops.javaVersion  → 运行时 Docker 基础镜像（Dockerfile FROM harbor.../jdk:XX）
    #   JAVA_CI_VERSION  → CI 编译 JDK 版本（.gitlab-ci.yml image: maven:3.9-eclipse-temurin-XX）
    #
    # 两者必须保持一致，否则会出现字节码版本不兼容（UnsupportedClassVersionError）。
    # eclipse-temurin 镜像的 JAVA_HOME 由镜像自动配置（/opt/java/openjdk），无需手动设置。
    #
    # 多版本项目配置方法：
    #   在 GitLab 项目级 Variables 中设置 JAVA_CI_VERSION=8（或 11/17/21）
    #   在 Apollo 项目 namespace 中设置 ops.javaVersion=8（或 11/17/21）
    #   在 pom.xml 中设置 <java.version>8</java.version>（或对应版本）
    #   三者对齐后，Spring Boot 2.x（Java 8/11）和 3.x（Java 17/21）均可正常运行。
    case "${javaVersion}" in
        "8")
            baseJavaImage="${HARBOR_URL}/${HARBOR_PROJECT}/jdk:8"
            ;;
        "11")
            baseJavaImage="${HARBOR_URL}/${HARBOR_PROJECT}/jdk:11"
            ;;
        "17")
            baseJavaImage="${HARBOR_URL}/${HARBOR_PROJECT}/jdk:17"
            ;;
        "21")
            baseJavaImage="${HARBOR_URL}/${HARBOR_PROJECT}/jdk:21"
            ;;
        *)
            echo "[ERROR] 不支持的 Java 版本: ${javaVersion}，支持 8/11/17/21"
            echo "[ERROR] 请同步设置：GitLab JAVA_CI_VERSION、Apollo ops.javaVersion、pom.xml <java.version>"
            exit 1
            ;;
    esac

    # Java 项目默认启用 Apollo（注入 -Dapp.id 和 -Dapollo.meta JVM 参数）
    supportApollo='true'

    # JVM 参数构建
    if echo "${javaCmdOptions}" | grep -qE '\-Xmx|\-Xms'; then
        echo "[ERROR] 请勿在属性 ops.javaCmdOptions 中设置 JVM 内存选项(-Xmx、-Xms)"
        exit 1
    fi

    javaCmdOptions="${javaCmdOptions} -Xmx${jvmMaxMemory}m -Xms${jvmMinMemory}m"

    if [ "${supportApollo}" = "true" ]; then
        javaCmdOptions="${javaCmdOptions} -Dapp.id=${appId} -Dapollo.meta=${APOLLO_META}"
    fi

    # OTel 链路追踪（双方案：bridge 主力 / agent 兜底）
    if [ "${supportOtel}" = "true" ]; then
        if [ "${otelMode}" = "agent" ]; then
            javaCmdOptions="${javaCmdOptions} -javaagent:/opt/otel/opentelemetry-javaagent.jar"
            echo "[INFO] OTel 链路追踪: 已启用 (Agent 模式，JDK ${javaVersion})"
        else
            # bridge 模式：由 pom.xml 中的 micrometer-tracing-bridge-otel 依赖实现，无需 javaagent
            echo "[INFO] OTel 链路追踪: 已启用 (Bridge 模式，JDK ${javaVersion})"
        fi
    else
        echo "[INFO] OTel 链路追踪: 未启用"
    fi

    # 应用端口校验
    checkPort

    # 优雅下线配置（滚动更新时主动注销 Consul 服务）
    # preStopCmd 仅保存 shell 命令字符串，YAML 模板中统一用 ["/bin/sh", "-c", "..."] 格式
    if [ "${k8sUpdateStrategy}" = "RollingUpdate" ]; then
        # 等待 5 秒让 Ingress 停止转发新请求，然后注销 Consul 服务
        preStopCmd="sleep 5 && curl -s -X PUT http://consul-${currentEnv}.renew.com:8500/v1/agent/service/deregister/${appId} || true"
        echo "[INFO] 优雅下线: 已启用（Consul 注销）"
    else
        preStopCmd="sleep 5"
        echo "[INFO] 优雅下线: 未启用（非滚动更新）"
    fi

    echo "[INFO] Java 版本: ${javaVersion}"
    echo "[INFO] 基础镜像: ${baseJavaImage}"
    echo "[INFO] JVM 参数: ${javaCmdOptions}"
}

# 用途：获取 HTML 应用专用的环境变量
function getHtmlEnv() {
    nodejsVersion=$(echo "${commonConfig}" | jq -r '.["ops.nodejsVersion"]')
    nodejsBuildCommand=$(echo "${commonConfig}" | jq -r '.["ops.nodejsBuildCommand"]')
    htmlPackageDirectory=$(echo "${commonConfig}" | jq -r '.["ops.htmlPackageDirectory"]')

    # 必填配置校验
    local missingConfigs=""

    if [ -z "${nodejsVersion}" ] || [ "${nodejsVersion}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.nodejsVersion"
    fi
    if [ -z "${nodejsBuildCommand}" ] || [ "${nodejsBuildCommand}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.nodejsBuildCommand"
    fi
    if [ -z "${htmlPackageDirectory}" ] || [ "${htmlPackageDirectory}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.htmlPackageDirectory"
    fi

    if [ -n "${missingConfigs}" ]; then
        echo "[ERROR] 缺少前端配置项:${missingConfigs}"
        echo "[HINT] 请在 Apollo tech.common namespace 或项目 namespace 中配置这些项"
        exit 1
    fi

    autoReuseImage="false"
    appPort=80

    # 前端运行时镜像固定为 nginx，构建时使用 nodejsVersion
    baseHtmlImage="${HARBOR_URL}/${HARBOR_PROJECT}/nginx:1.27"

    echo "[INFO] Node.js 版本: ${nodejsVersion}（构建阶段）"
    echo "[INFO] 基础镜像: ${baseHtmlImage}（运行时）"
}

# 用途：获取 Python 应用专用的环境变量
function getPythonEnv() {
    pyBuildCommand=$(echo "${commonConfig}" | jq -r '.["ops.pyBuildCommand"]')
    pyStartCommand=$(echo "${commonConfig}" | jq -r '.["ops.pyStartCommand"]')
    autoReuseImage=$(echo "${commonConfig}" | jq -r '.["ops.autoReuseImage"]')
    appHealthUri=$(echo "${commonConfig}" | jq -r '.["ops.appHealthUri"]')
    appPort=$(echo "${commonConfig}" | jq -r '.["ops.appPort"] // "null"')
    pythonVersion=$(echo "${commonConfig}" | jq -r '.["ops.pythonVersion"]')

    # 必填配置校验
    local missingConfigs=""

    if [ -z "${pyBuildCommand}" ] || [ "${pyBuildCommand}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.pyBuildCommand"
    fi
    if [ -z "${pyStartCommand}" ] || [ "${pyStartCommand}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.pyStartCommand"
    fi
    if [ -z "${autoReuseImage}" ] || [ "${autoReuseImage}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.autoReuseImage"
    fi
    if [ -z "${appHealthUri}" ] || [ "${appHealthUri}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.appHealthUri"
    fi
    if [ -z "${pythonVersion}" ] || [ "${pythonVersion}" = "null" ]; then
        missingConfigs="${missingConfigs} ops.pythonVersion"
    fi

    if [ -n "${missingConfigs}" ]; then
        echo "[ERROR] 缺少 Python 配置项:${missingConfigs}"
        echo "[HINT] 请在 Apollo tech.common namespace 或项目 namespace 中配置这些项"
        exit 1
    fi

    # Python 版本校验与基础镜像选择
    case "${pythonVersion}" in
        "3.9"|"3.10"|"3.11"|"3.12")
            baseImage="${HARBOR_URL}/${HARBOR_PROJECT}/python:${pythonVersion}"
            ;;
        *)
            echo "[ERROR] 不支持的 Python 版本: ${pythonVersion}，支持 3.9/3.10/3.11/3.12"
            exit 1
            ;;
    esac

    checkPort

    echo "[INFO] Python 版本: ${pythonVersion}"
    echo "[INFO] 基础镜像: ${baseImage}"
}

# 用途：应用端口校验
function checkPort() {
    if [ -z "${appPort}" ] || [ "${appPort}" = "null" ]; then
        appConfig=$(curl -s "${APOLLO_META}/configs/${appId}/default/application" | jq -r '.configurations')
        serverPort=$(echo "${appConfig}" | jq -r '.["server.port"]')
        if [ -n "${serverPort}" ] && [ "${serverPort}" != "null" ]; then
            appPort="${serverPort}"
        else
            echo "[ERROR] 请设置 ops.appPort 或在 Apollo application namespace 中配置 server.port"
            exit 1
        fi
    fi
    echo "[INFO] 应用端口: ${appPort}"
}

# 用途：检查 Harbor 中镜像是否存在
# 参数：镜像标签
# 返回值：0 代表存在，1 代表不存在
function checkImageExists() {
    local imageTag="$1"
    local harborApi="http://${HARBOR_URL}/api/v2.0"

    # 使用 Harbor API 检查镜像是否存在
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "admin:${HARBOR_PASSWORD}" \
        "${harborApi}/projects/${HARBOR_PROJECT}/repositories/${appId}/artifacts/${imageTag}" 2>/dev/null)

    if [ "${response}" = "200" ]; then
        return 0
    else
        return 1
    fi
}

# 用途：尝试复用已有镜像
# 返回值：0 代表成功复用，1 代表需要构建
function reuseImage() {
    if [ "${autoReuseImage}" != "true" ]; then
        return 1
    fi

    echo "[INFO] 检查镜像是否已存在: ${HARBOR_URL}/${HARBOR_PROJECT}/${appId}:${imageTag}"

    if checkImageExists "${imageTag}"; then
        echo "[INFO] 镜像已存在，跳过构建: ${HARBOR_URL}/${HARBOR_PROJECT}/${appId}:${imageTag}"
        return 0
    fi

    echo "[INFO] 镜像不存在，需要构建"
    return 1
}

# 用途：镜像构建
function buildImage() {
    local fullImageName="$1"
    echo "[INFO] 开始构建镜像: ${fullImageName}"

    if ! docker build \
        --label "org.opencontainers.image.authors=${GITLAB_USER_EMAIL}" \
        --label "org.opencontainers.image.source=${CI_PROJECT_URL}" \
        -t "${fullImageName}" .; then
        echo "[ERROR] 镜像构建失败"
        exit 1
    fi

    echo "[INFO] 推送镜像到 Harbor"
    if ! docker push "${fullImageName}"; then
        echo "[ERROR] 镜像推送失败"
        exit 1
    fi

    # 清理本地镜像
    docker rmi "${fullImageName}" 2>/dev/null || true
}

# 用途：Java 应用构建（支持镜像复用）
function prepareJavaImage() {
    # 尝试复用镜像
    if reuseImage; then
        return 0
    fi

    echo "[INFO] 使用版本：Java ${javaVersion}, Maven ${mavenVersion}"
    echo "[INFO] 构建命令：${mavenBuildCommand}"

    cd "${appSubDir}"

    # 检查是否已有 jar 包（CI/CD Pipeline 中 jar stage 已构建）
    local jarCount=$(ls target/*.jar 2>/dev/null | wc -l)
    if [ "${jarCount}" -gt 0 ]; then
        echo "[INFO] 发现已有 ${jarCount} 个 jar 包，跳过 Maven 构建"
        echo "[INFO] jar 文件列表："
        ls -la target/*.jar 2>/dev/null || true
    else
        echo "[INFO] 未发现 jar 包，执行 Maven 构建"
        eval "${mavenBuildCommand}"
        if [ $? -ne 0 ]; then
            echo "[ERROR] Maven 编译失败"
            exit 1
        fi
    fi

    # 生成 Dockerfile
    if [ -f "Dockerfile" ]; then
        echo "[INFO] 使用项目中的 Dockerfile"
    else
        echo "[INFO] 生成 Dockerfile"
        cat > Dockerfile <<EOF
FROM ${baseJavaImage}
WORKDIR /app
COPY target/*.jar /app/app.jar
# 使用 exec 替换 shell 进程，确保 java 为 PID 1，可直接接收 K8s 发出的 SIGTERM 信号，保证优雅停机生效
ENTRYPOINT ["/bin/sh", "-c", "exec java \${JAVA_OPTS} -jar /app/app.jar"]
EOF
    fi

    buildImage "${HARBOR_URL}/${HARBOR_PROJECT}/${appId}:${imageTag}"
    cd "${CI_PROJECT_DIR}"
}

# 用途：HTML 应用构建（支持镜像复用）
function prepareHtmlImage() {
    # 尝试复用镜像（前端项目通常不启用复用，因为构建产物不同）
    if [ "${autoReuseImage}" = "true" ] && reuseImage; then
        return 0
    fi

    echo "[INFO] 使用版本：Node.js ${nodejsVersion}"

    cd "${appSubDir}"

    # 如果构建产物已存在（CI build 阶段已产出 artifacts），跳过构建
    if [ -d "${htmlPackageDirectory}" ] && [ "$(ls -A ${htmlPackageDirectory} 2>/dev/null)" ]; then
        echo "[INFO] 发现已有构建产物 ${htmlPackageDirectory}/，跳过前端构建"
    else
        echo "[INFO] 构建命令：${nodejsBuildCommand}"
        eval "${nodejsBuildCommand}"

        if [ $? -ne 0 ]; then
            echo "[ERROR] 前端编译失败"
            exit 1
        fi
    fi

    # 生成 nginx 配置
    if [ "${appDomainReverseProxyUri}" = "/" ]; then
        cat > nginx.default.conf <<EOF
server {
    listen 80;
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html index.htm;

    location / {
        try_files \$uri /index.html;
    }
}
EOF
    else
        cat > nginx.default.conf <<EOF
server {
    listen 80;
    server_name localhost;

    location / {
        root /usr/share/nginx/html;
        return 200;
    }

    location ${appDomainReverseProxyUri} {
        alias /usr/share/nginx/html/;
        try_files \$uri ${appDomainReverseProxyUri}/index.html;
    }
}
EOF
    fi

    # 生成 Dockerfile
    if [ -f "Dockerfile" ]; then
        echo "[INFO] 使用项目中的 Dockerfile"
    else
        echo "[INFO] 生成 Dockerfile"
        cat > Dockerfile <<EOF
FROM ${baseHtmlImage}
COPY nginx.default.conf /etc/nginx/conf.d/default.conf
COPY ${htmlPackageDirectory} /usr/share/nginx/html/
EOF
    fi

    buildImage "${HARBOR_URL}/${HARBOR_PROJECT}/${appId}:${imageTag}"
    cd "${CI_PROJECT_DIR}"
}

# 用途：Python 应用构建（支持镜像复用）
function preparePythonImage() {
    # 尝试复用镜像
    if [ "${autoReuseImage}" = "true" ] && reuseImage; then
        return 0
    fi

    echo "[INFO] 使用版本：Python ${pythonVersion}"

    cd "${appSubDir}"

    # 检查 .dockerignore，避免将 .git、__pycache__、.venv 等打入镜像导致体积膨胀
    if [ ! -f ".dockerignore" ]; then
        echo "[WARN] 未发现 .dockerignore，建议在项目根目录添加，排除 .git/ __pycache__/ .venv/ *.pyc 等，可显著减小镜像体积"
    fi

    if [ -f "Dockerfile" ]; then
        echo "[INFO] 使用项目中的 Dockerfile"
    else
        cat > Dockerfile <<EOF
FROM ${baseImage}
WORKDIR /app
COPY . /app/
RUN ${pyBuildCommand}
EOF
    fi

    buildImage "${HARBOR_URL}/${HARBOR_PROJECT}/${appId}:${imageTag}"
    cd "${CI_PROJECT_DIR}"
}

# 用途：K8s Java 应用部署
function k8sJavaDeployment() {
    echo "[INFO] 部署 Java 应用到 K3s"

    # 构建滚动更新策略
    local strategyYaml=""
    if [ "${k8sUpdateStrategy}" = "RollingUpdate" ]; then
        strategyYaml="type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0"
    else
        strategyYaml="type: ${k8sUpdateStrategy}"
    fi

    # 构建 OTel 环境变量块（仅当 supportOtel=true 时注入）
    local otelEnvBlock=""
    if [ "${supportOtel}" = "true" ]; then
        otelEnvBlock="        - name: OTEL_SERVICE_NAME
          value: \"${appId}\"
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: \"http://otel-${domainEnv}.renew.com:4317\"
        - name: OTEL_EXPORTER_OTLP_PROTOCOL
          value: \"grpc\"
        - name: OTEL_RESOURCE_ATTRIBUTES
          value: \"deployment.environment=${currentEnv},service.namespace=${currentEnv}\"
        - name: OTEL_METRICS_EXPORTER
          value: \"none\"
        - name: OTEL_LOGS_EXPORTER
          value: \"otlp\"
        - name: OTEL_TRACES_EXPORTER
          value: \"otlp\""
        # Agent 模式下关闭 Micrometer Bridge，避免重复导出指标
        if [ "${otelMode}" = "agent" ]; then
            otelEnvBlock="${otelEnvBlock}
        - name: OTEL_INSTRUMENTATION_MICROMETER_ENABLED
          value: \"false\""
        fi
    fi

    kubectl --kubeconfig="${KUBECONFIG}" apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${appId}
  namespace: ${currentEnv}
  labels:
    app: ${appId}
spec:
  replicas: ${k8sReplicas}
  strategy:
    ${strategyYaml}
  selector:
    matchLabels:
      app: ${appId}
  template:
    metadata:
      labels:
        app: ${appId}
        version: ${notFixedValue}
    spec:
      terminationGracePeriodSeconds: 180
      containers:
      - name: ${appId}
        image: ${HARBOR_URL}/${HARBOR_PROJECT}/${appId}:${imageTag}
        imagePullPolicy: Always
        ports:
        - containerPort: ${appPort}
        env:
        - name: JAVA_OPTS
          value: "${javaCmdOptions}"
        - name: SPRING_PROFILES_ACTIVE
          value: "${currentEnv}"
${otelEnvBlock}
        resources:
          requests:
            cpu: "100m"
            memory: "${containerMinMemory}Mi"
          limits:
            cpu: "${appCpuLimit}"
            memory: "${containerMaxMemory}Mi"
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "${preStopCmd}"]
        livenessProbe:
          httpGet:
            path: ${appHealthUri}
            port: ${appPort}
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 18
        readinessProbe:
          httpGet:
            path: ${appHealthUri}
            port: ${appPort}
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 18
        volumeMounts:
$(k8sGenerateVolumesInfo 'volumeMounts')
      volumes:
$(k8sGenerateVolumesInfo 'volumes')
      imagePullSecrets:
      - name: harbor-registry
EOF

    if [ $? -ne 0 ]; then
        echo "[ERROR] Deployment 执行失败"
        exit 1
    fi
}

# 用途：K8s HTML 应用部署
function k8sHtmlDeployment() {
    echo "[INFO] 部署 HTML 应用到 K3s"

    # 构建滚动更新策略（与 Java/Python 保持一致）
    local strategyYaml=""
    if [ "${k8sUpdateStrategy}" = "RollingUpdate" ]; then
        strategyYaml="type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0"
    else
        strategyYaml="type: ${k8sUpdateStrategy}"
    fi

    kubectl --kubeconfig="${KUBECONFIG}" apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${appId}
  namespace: ${currentEnv}
  labels:
    app: ${appId}
spec:
  replicas: ${k8sReplicas}
  strategy:
    ${strategyYaml}
  selector:
    matchLabels:
      app: ${appId}
  template:
    metadata:
      labels:
        app: ${appId}
        version: ${notFixedValue}
    spec:
      terminationGracePeriodSeconds: 60
      containers:
      - name: ${appId}
        image: ${HARBOR_URL}/${HARBOR_PROJECT}/${appId}:${imageTag}
        imagePullPolicy: Always
        ports:
        - containerPort: ${appPort}
        resources:
          requests:
            cpu: "10m"
            memory: "32Mi"
          limits:
            cpu: "${appCpuLimit}"
            memory: "${appMemoryLimit}Mi"
        livenessProbe:
          httpGet:
            path: /
            port: ${appPort}
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /
            port: ${appPort}
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 5
          failureThreshold: 3
      imagePullSecrets:
      - name: harbor-registry
EOF

    if [ $? -ne 0 ]; then
        echo "[ERROR] Deployment 执行失败"
        exit 1
    fi
}

# 用途：K8s Python 应用部署
function k8sPythonDeployment() {
    echo "[INFO] 部署 Python 应用到 K3s"

    # 构建滚动更新策略
    local strategyYaml=""
    if [ "${k8sUpdateStrategy}" = "RollingUpdate" ]; then
        strategyYaml="type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0"
    else
        strategyYaml="type: ${k8sUpdateStrategy}"
    fi

    kubectl --kubeconfig="${KUBECONFIG}" apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${appId}
  namespace: ${currentEnv}
  labels:
    app: ${appId}
spec:
  replicas: ${k8sReplicas}
  strategy:
    ${strategyYaml}
  selector:
    matchLabels:
      app: ${appId}
  template:
    metadata:
      labels:
        app: ${appId}
        version: ${notFixedValue}
    spec:
      terminationGracePeriodSeconds: 60
      containers:
      - name: ${appId}
        image: ${HARBOR_URL}/${HARBOR_PROJECT}/${appId}:${imageTag}
        imagePullPolicy: Always
        command: ["/bin/sh", "-c", "${pyStartCommand}"]
        ports:
        - containerPort: ${appPort}
        env:
        - name: RUN_ENV
          value: "${currentEnv}"
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
          limits:
            cpu: "${appCpuLimit}"
            memory: "${appMemoryLimit}Mi"
        livenessProbe:
          httpGet:
            path: ${appHealthUri}
            port: ${appPort}
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 18
        readinessProbe:
          httpGet:
            path: ${appHealthUri}
            port: ${appPort}
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 18
      imagePullSecrets:
      - name: harbor-registry
EOF

    if [ $? -ne 0 ]; then
        echo "[ERROR] Deployment 执行失败"
        exit 1
    fi
}

# 用途：创建 HPA
function k8sHPA() {
    if [ -z "${k8sReplicasMin}" ] || [ -z "${k8sReplicasMax}" ]; then
        echo "[INFO] 未配置 HPA，跳过"
        return 0
    fi

    # HPA 场景下校验必填配置
    if [ -z "${k8sTargetCPU}" ] || [ "${k8sTargetCPU}" = "null" ]; then
        echo "[ERROR] 启用 HPA 时必须配置 ops.k8sTargetCPU"
        exit 1
    fi
    if [ -z "${k8sTargetMemory}" ] || [ "${k8sTargetMemory}" = "null" ]; then
        echo "[ERROR] 启用 HPA 时必须配置 ops.k8sTargetMemory"
        exit 1
    fi

    echo "[INFO] 创建 HPA: ${k8sReplicasMin} - ${k8sReplicasMax} 副本"

    kubectl --kubeconfig="${KUBECONFIG}" apply -f - <<EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ${appId}-hpa
  namespace: ${currentEnv}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ${appId}
  minReplicas: ${k8sReplicasMin}
  maxReplicas: ${k8sReplicasMax}
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: ${k8sTargetCPU}
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: ${k8sTargetMemory}
EOF
}

# 用途：创建 PDB（多副本自动启用）
# 规则：
#   - k8sReplicas >= 2：自动创建 PDB，默认 minAvailable=1，可通过 ops.k8sPdbMinAvailable 覆盖
#   - k8sReplicas = 1：不创建 PDB（单副本无法满足 minAvailable >= 1）
function k8sPDB() {
    # 单副本不创建 PDB
    if [ "${k8sReplicas}" -lt 2 ]; then
        echo "[INFO] 单副本服务不创建 PDB"
        return 0
    fi

    # 多副本自动设置默认值 minAvailable=1
    if [ -z "${k8sPdbMinAvailable}" ] || [ "${k8sPdbMinAvailable}" = "null" ]; then
        k8sPdbMinAvailable=1
    fi

    # 用户显式设置为 0 表示禁用 PDB
    if [ "${k8sPdbMinAvailable}" = "0" ]; then
        echo "[INFO] PDB 已禁用 (k8sPdbMinAvailable=0)"
        return 0
    fi

    # 校验 minAvailable 必须小于副本数，否则节点维护时 kubectl drain 会被 PDB 永久阻塞
    if [ "${k8sPdbMinAvailable}" -ge "${k8sReplicas}" ]; then
        echo "[ERROR] ops.k8sPdbMinAvailable (${k8sPdbMinAvailable}) 必须小于 ops.k8sReplicas (${k8sReplicas})，否则节点维护时无法驱逐 Pod"
        exit 1
    fi

    echo "[INFO] 创建 PDB: minAvailable=${k8sPdbMinAvailable} (副本数: ${k8sReplicas})"

    kubectl --kubeconfig="${KUBECONFIG}" apply -f - <<EOF
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: ${appId}-pdb
  namespace: ${currentEnv}
spec:
  minAvailable: ${k8sPdbMinAvailable}
  selector:
    matchLabels:
      app: ${appId}
EOF
}

# 用途：K8s Service
function k8sService() {
    echo "[INFO] 创建 Service"

    kubectl --kubeconfig="${KUBECONFIG}" apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${appId}
  namespace: ${currentEnv}
  labels:
    app: ${appId}
spec:
  ports:
  - name: http
    protocol: TCP
    port: ${appPort}
    targetPort: ${appPort}
  selector:
    app: ${appId}
EOF
}

# 用途：K8s Ingress
function k8sIngress() {
    local domain="$1"
    local ingressName="$2"

    echo "[INFO] 创建 Ingress: ${domain}"

    kubectl --kubeconfig="${KUBECONFIG}" apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${ingressName}
  namespace: ${currentEnv}
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  rules:
  - host: ${domain}
    http:
      paths:
      - path: ${appDomainReverseProxyUri}
        pathType: Prefix
        backend:
          service:
            name: ${appId}
            port:
              number: ${appPort}
EOF
}

# 用途：生成存储卷信息
function k8sGenerateVolumesInfo() {
    if [ "$1" = "volumes" ] && [ "${persistentStorage}" = "true" ]; then
        echo "      - name: data-volume"
        echo "        persistentVolumeClaim:"
        echo "          claimName: data-volume-${appId}"
    elif [ "$1" = "volumeMounts" ] && [ "${persistentStorage}" = "true" ]; then
        echo "        - name: data-volume"
        echo "          mountPath: ${persistentStoragePath}"
    fi
}

# 用途：创建 PVC
function k8sPVC() {
    if [ "${persistentStorage}" != "true" ]; then
        return 0
    fi

    echo "[INFO] 创建 PVC: ${persistentStorageSize}Gi"

    kubectl --kubeconfig="${KUBECONFIG}" apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-volume-${appId}
  namespace: ${currentEnv}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ${k8sStorageClass}
  resources:
    requests:
      storage: ${persistentStorageSize}Gi
EOF
}

# 用途：应用失败日志输出
function appFailLog() {
    echo "[ERROR] 应用部署失败，查看日志："
    local podName
    podName=$(kubectl --kubeconfig="${KUBECONFIG}" get pods -n "${currentEnv}" \
        -l "app=${appId}" --sort-by='.metadata.creationTimestamp' \
        -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || true)

    if [ -z "${podName}" ]; then
        # Pod 从未创建成功（镜像拉取失败、资源不足等），输出 Deployment Events 帮助定位
        echo "[ERROR] 未找到运行中的 Pod，输出 Deployment Events："
        kubectl --kubeconfig="${KUBECONFIG}" describe deployment "${appId}" -n "${currentEnv}" 2>/dev/null | tail -30 || true
        return
    fi

    # 不带 -f，输出最后 300 行后直接返回，避免 CI Job 永久挂起
    kubectl --kubeconfig="${KUBECONFIG}" logs --tail 300 "${podName}" -c "${appId}" -n "${currentEnv}" 2>/dev/null || \
        kubectl --kubeconfig="${KUBECONFIG}" logs --tail 300 "${podName}" -n "${currentEnv}" 2>/dev/null || true
}

# 用途：发送钉钉通知（ActionCard 格式）
function sendDingTalk() {
    local status="$1"
    local endTime
    local sumTime
    endTime=$(date +%Y%m%d-%H:%M:%S)
    endTime_s=$(date +%s)
    sumTime=$((endTime_s - startTime_s))

    if [ -z "${DINGTALK_WEBHOOK}" ]; then
        echo "[INFO] 未配置钉钉 Webhook，跳过通知"
        return 0
    fi

    local emoji=""
    local color=""
    case "${status}" in
        "成功")
            emoji="✅"
            color="#02b340"
            ;;
        "失败")
            emoji="❌"
            color="#ff0000"
            ;;
        "开始")
            emoji="🚀"
            color="#0066cc"
            ;;
        *)
            emoji="ℹ️"
            color="#666666"
            ;;
    esac

    # 构建消息内容
    local title="Gitlab 持续交付信息"
    local text=""
    if [ "${status}" = "开始" ]; then
        text="**<font color=\"${color}\">${emoji} 【部署${status}】</font>**  \n\n\
**项目名称:** ${appId}  \n\n\
**部署环境:** ${currentEnv}  \n\n\
**分支/标签:** ${CI_COMMIT_REF_NAME}  \n\n\
**操作人:** ${GITLAB_USER_LOGIN}"
    else
        text="**<font color=\"${color}\">${emoji} 【部署${status}】</font>**  \n\n\
**项目名称:** ${appId}  \n\n\
**部署环境:** ${currentEnv}  \n\n\
**分支/标签:** ${CI_COMMIT_REF_NAME}  \n\n\
**耗时:** ${sumTime} 秒  \n\n\
**操作人:** ${GITLAB_USER_LOGIN}"
    fi

    # 发送钉钉通知（ActionCard 格式，带重试机制）
    local maxRetries=3
    local retryInterval=2
    local retryCount=0
    local sendSuccess=false

    while [ ${retryCount} -lt ${maxRetries} ]; do
        # 使用 heredoc 构建JSON，避免转义问题
        local payload=$(cat <<PAYLOAD_EOF
{
    "msgtype": "actionCard",
    "actionCard": {
        "title": "${title}",
        "text": "${text}",
        "singleTitle": "查看详情",
        "singleURL": "dingtalk://dingtalkclient/page/link?url=${CI_JOB_URL}&pc_slide=false"
    }
}
PAYLOAD_EOF
)
        if curl -s -m 5 "${DINGTALK_WEBHOOK}" \
            -H 'Content-Type: application/json;charset=utf-8' \
            -d "${payload}" > /dev/null 2>&1; then
            sendSuccess=true
            break
        fi

        retryCount=$((retryCount + 1))
        if [ ${retryCount} -lt ${maxRetries} ]; then
            echo "[WARN] 钉钉通知发送失败，${retryInterval}秒后重试 (${retryCount}/${maxRetries})"
            sleep ${retryInterval}
        fi
    done

    if [ "${sendSuccess}" = "false" ]; then
        echo "[WARN] 钉钉通知发送失败，已重试 ${maxRetries} 次"
    fi
}

#===============================================================================
# 主函数
#===============================================================================
function main() {
    echo "=========================================="
    echo "  Tech Stack CI/CD 部署脚本"
    echo "  时间: ${startTime}"
    echo "=========================================="

    getAppType
    getCommonEnv

    # 发送部署开始通知
    sendDingTalk "开始"

    # 确保 K8s namespace 和 Harbor 密钥存在
    ensureK8sNamespace

    # 先创建 PVC（Deployment 挂载 PVC 时需提前存在，避免 Pod Pending）
    k8sPVC

    case "${appType}" in
        "java")
            getJavaEnv
            prepareJavaImage
            k8sJavaDeployment
            ;;
        "html")
            getHtmlEnv
            prepareHtmlImage
            k8sHtmlDeployment
            ;;
        "python")
            getPythonEnv
            preparePythonImage
            k8sPythonDeployment
            ;;
    esac

    # 创建 HPA（如果配置了）
    k8sHPA

    # 创建 PDB（如果配置了）
    k8sPDB

    # 始终创建 Service（供 Prometheus 抓取指标、K8s 内部访问等）
    k8sService

    # 仅在配置了域名时创建 Ingress
    if [ -n "${appDomain}" ] && [ "${appDomain}" != "null" ]; then
        local i=0
        for domain in ${appDomain}; do
            i=$((i + 1))
            if [ $i -eq 1 ]; then
                ingressName="${appId}"
            else
                ingressName="${appId}-${i}"
            fi
            k8sIngress "${domain}" "${ingressName}"
        done
    fi

    # 等待部署完成
    echo "[INFO] 等待部署完成..."
    if ! kubectl --kubeconfig="${KUBECONFIG}" rollout status deployment/${appId} -n "${currentEnv}" --timeout=4m; then
        appFailLog
        sendDingTalk "失败"
        exit 1
    fi

    echo "[INFO] 部署成功！"
    echo "[INFO] 发布人: ${GITLAB_USER_LOGIN}"
    sendDingTalk "成功"
}

main
