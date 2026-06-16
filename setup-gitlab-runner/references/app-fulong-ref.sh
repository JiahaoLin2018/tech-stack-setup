#!/bin/bash
#用途：获取当前脚本执行前的时间
startTime=`date +%Y%m%d-%H:%M:%S`
startTime_s=`date +%s`


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
	# 应用ID
	if [ x${APP_ID} == x ]; then
		appId=${CI_PROJECT_NAME}
	else
		appId=${APP_ID}
	fi
	
	if [ -z "`echo ${appId} | grep -E -o '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$'`" ]; then
		echo "[ERROR] 应用ID \"${appId}\" 不符合规范。它只能由小写字母、数字、短横线(-)组成，并以小写字母或数字开始和结尾。"
		exit 1
	fi
	
	# 应用所在子目录
	if [ x${APP_SUB_DIR} == x ]; then
			appSubDir="."
	else
			appSubDir="./${APP_SUB_DIR}"
	fi
	
	# 当前环境
	if [ x${CI_ENVIRONMENT_NAME} == x ]; then
			echo "[ERROR] 未设置应用部署到哪个环境，CI_ENVIRONMENT_NAME 环境变量为空"
			exit 1
	else
		currentEnv=${CI_ENVIRONMENT_NAME}
    fi
	
	# 只有特定用户才能执行
	userList='root user1 user2 user3 user4 user5 user6' 
	if [[ "${CI_PROJECT_NAMESPACE}" =~ "algorithm1" ]] || [[ "${CI_PROJECT_NAME}" =~ "bbe" ]] || [[ "${CI_PROJECT_NAMESPACE}" =~ "labor" ]]; then
		echo "[INFO] 本项目不做用户校验"
	elif [ -z "`echo \"${userList}\" | grep ${GITLAB_USER_LOGIN}`" ]; then
		echo "[INFO] 当前用户为：${GITLAB_USER_LOGIN}"
		echo "[ERROR] 只有被授权用户才能进行生产环境应用部署"
		exit 1
	else
		:
    fi
	
	# 镜像仓库地址
	repoAddress='CHANGE_ME_REGISTRY_ADDRESS'
	# 镜像标签
	imageTag=$(echo $CI_COMMIT_SHA|cut -b 1-8)
	# 加入该字段，以使每次运行本脚本时deployment的定义都不一样，强制k8s对应用进行更新
	notFixedValue="value-`date +%Y%m%d%H%M%S`"

	# 获取apollo中的配置
	commonConfig=$(curl -s http://config.${currentEnv}.bdata.api.example.com/configs/${appId}/default/tech.common |jq -r '.configurations')
	appDomain=$(echo ${commonConfig} | jq -r '.["ops.appDomain"]')
	appDomainReverseProxyUri=$(echo ${commonConfig} | jq -r '.["ops.appDomainReverseProxyUri"]')
	appCpuLimit=$(echo ${commonConfig} | jq -r '.["ops.appCpuLimit"]')
	appMemoryLimit=$(echo ${commonConfig} | jq -r '.["ops.appMemoryLimit"]')
	k8sReplicas=$(echo ${commonConfig} | jq -r '.["ops.k8sReplicas"]')
	k8sUpdateStrategy=$(echo ${commonConfig} | jq -r '.["ops.k8sUpdateStrategy"]')
	persistentStorage=$(echo ${commonConfig} | jq -r '.["ops.persistentStorage"]')
	persistentStorageSize=$(echo ${commonConfig} | jq -r '.["ops.persistentStorageSize"]')
	persistentStoragePath=$(echo ${commonConfig} | jq -r '.["ops.persistentStoragePath"]')
	k8sGPU=$(echo ${commonConfig} | jq -r '.["ops.k8sGPU"]')

	# cpu值校验
	if [ -z "`echo ${appCpuLimit} | grep -E -o '^([1-9][0-9]*|[0-9]+\.[1-9])$'`" ]; then
		echo "[ERROR] 属性 ops.appCpuLimit 值应为小数或正整数"
		exit 1
	fi
	
	# 内存值校验
	if [ -z "`echo ${appMemoryLimit} | grep -E -o '^[1-9][0-9]*$'`" ]; then
		echo "[ERROR] 属性 ops.appMemoryLimit 值应为正整数"
		exit 1
	fi
	
	# 持久化存储值校验
	if [ -z "`echo ${persistentStorage} | grep -E '^(true|false)$'`" ]; then
		echo "[ERROR] 属性 ops.persistentStorage 设置错误。取值范围应为：true、false"
		exit 1
	fi
	
	if [ -z "`echo ${persistentStorageSize} | grep -E -o '^[1-9][0-9]*$'`" ]; then
		echo "[ERROR] 属性 ops.persistentStorageSize 值应为正整数"
		exit 1
	fi
	
	if [ -z "`echo ${persistentStoragePath} | grep -E -o '^/[a-zA-Z/]+$'`" ]; then
		echo "[ERROR] 属性 ops.persistentStorageSize 值应为/开头并且是由a-z、A-Z、/ 组成"
		exit 1
	fi
        
	# 引入额外配置文件
	if [ -d "/opt/projectFiles/${appId}" ]; then
		cp -r /opt/projectFiles/${appId} ${appSubDir}/${appId}
	fi
	
	k8sRestartPolicy='Always'
	k8sStorageClass='alicloud-nas-subpath'
	echo "[INFO] 是否启用GPU：${k8sGPU}"
}

# 用途：获取Java应用专用的环境变量
function getJavaEnv() {
	# 获取apollo中的配置
	javaVersion=$(echo ${commonConfig} | jq -r '.["ops.javaVersion"]')
	mavenBuildCommand=$(echo ${commonConfig} | jq -r '.["ops.mavenBuildCommand"]')
	javaCmdOptions=$(echo ${commonConfig} | jq -r '.["ops.javaCmdOptions"]')
	autoReuseImage=$(echo ${commonConfig} | jq -r '.["ops.autoReuseImage"]')
        appHealthUri=$(echo ${commonConfig} | jq -r '.["ops.appHealthUri"]')
        consulCluster=$(echo ${commonConfig} | jq -r '.["ops.consulCluster"]')
	filebeatConfigMap=$(echo ${commonConfig} | jq -r '.["ops.filebeatConfigMap"]')
        appPort=$(echo ${commonConfig} | jq -r '.["ops.appPort"]')
	logIndex=$(echo ${commonConfig} | jq -r '.["ops.logIndex"]')
        consulVersion=$(echo ${commonConfig} | jq -r '.["ops.consulVersion"]')
	# maven版本
	mavenVersion='3.5'
	# consul版本
	#consulVersion='1.5.3'
	# 启用pinpoint
        if [[ "${CI_PROJECT_NAMESPACE}" =~ "labor" ||  "${CI_PROJECT_NAME}" =~  "shanks-manage" ||  "${CI_PROJECT_NAME}" =~  "gazelle-model-assemble"   || "${CI_PROJECT_NAME}" =~  "shinji-engine-manage"  ||  "${CI_PROJECT_NAME}" =~  "sanji-monitor"   || "${CI_PROJECT_NAME}" =~ "bbe-credit-backend" || "${CI_PROJECT_NAME}" =~ "rayleigh-inside-gateway" || "${CI_PROJECT_NAME}" =~ "shinji" || "${CI_PROJECT_NAME}" =~ "aegis" || "${CI_PROJECT_NAME}" =~ "roger-quota-batch" ]];then
                supportPinpoint='false'
        else 
                supportPinpoint='true'
        fi
	# supportPinpoint='true'
	# 根据consulCluster来自动生成consulDatacenter的值
	case "${consulCluster}" in
		"devmain")
			consulDatacenter='dev';;
		"devbbe")
			consulDatacenter='devbbe';;
		"fwsmain")
			consulDatacenter='fws';;
		"fat")
			consulDatacenter='fat';;
		"fatbbe")
			consulDatacenter='fatbbe';;
		"uat")
			consulDatacenter='uat';;
		"uatbbe")
			consulDatacenter='uatbbe';;
		"prod")
			consulDatacenter='hx';;
		"fk")
			consulDatacenter='fk';;
		"labor")
			consulDatacenter='labor';;
		"bbe")
			consulDatacenter='bbe';;
		*)
			echo '[ERROR] 属性ops.consulCluster值设置错误'
			exit 1
			;;
	esac
	# 内存值设置
	containerMaxMemory=$((appMemoryLimit * 2))
	containerMinMemory=$((appMemoryLimit / 2))
	jvmMaxMemory=${appMemoryLimit}
	jvmMinMemory=${containerMinMemory}
        # 根据滚动更新策略来判定容器停止前所需执行的操作(解注册consul服务)
        if [ "${k8sUpdateStrategy}" = "RollingUpdate" ];then
                preStopCommand='["/bin/sh","-c","curl -s http://vsapi.bdata.api.example.com/deregister.sh | sh"]'
        else
                preStopCommand='["/bin/sh","-c","echo"]'
        fi
	# java版本校验
        case "${javaVersion}" in
               "8")
                        export JAVA_HOME="/usr/lib/jvm/java-8"
			export baseJavaImage="${repoAddress}/library/jdk:1.8.0"
                        ;;
                "11")
                        export JAVA_HOME="/usr/lib/jvm/java-11"
			export baseJavaImage="${repoAddress}/library/jdk:11.0.5"
                        ;;
                "17")
                        export JAVA_HOME="/usr/lib/jvm/java-17"
                        export baseJavaImage="${repoAddress}/library/jdk:17.0.5"
                        ;;
                "21")
                        export JAVA_HOME="/usr/lib/jvm/java-21"
                        export baseJavaImage="${repoAddress}/library/jdk:21.0.1"
                        ;;

                *)
                        echo "[ERROR] 错误的java版本号"
                        exit 1
                        ;;
        esac
        export PATH=${JAVA_HOME}/bin:$PATH
	# 应用自身是否支持apollo
	if [ "${mavenBuildCommand}" == "mvn clean install -Dmaven.test.skip=true" ]; then
		supportApollo='true'
	else
		supportApollo='false'
                echo "[ERROR] 不再支持非Apollo项目使用容器发布，请将项目接入Apollo后找运维处理。"
                exit 1
	fi
	# java命令行选项校验
        if [ -n "`echo ${javaCmdOptions} | grep -E -o '\-Xmx|\-Xms'`" ]; then
                echo "[ERROR] 请勿在属性 ops.javaCmdOptions 中设置jvm内存选项(-Xmx、-Xms)"
                exit 1
        fi
	javaCmdOptions="${javaCmdOptions} -Xmx${jvmMaxMemory}m -Xms${jvmMinMemory}m"
        if [ "${supportApollo}" == "true" ]; then
                javaCmdOptions="${javaCmdOptions} -Dapp.id=${appId} -Dapollo.meta=http://config.${currentEnv}.bdata.api.example.com"
        fi
        if [ "${supportPinpoint}" == "true" ]; then
                javaCmdOptions="${javaCmdOptions} -Dpinpoint.applicationName=$(echo ${appId}|rev|cut -c -19|rev|sed "s/^-//g;s/$/.${currentEnv}/g") -javaagent:/app/lib/pinpoint-bootstrap.jar"
        fi
        if [[ "${CI_PROJECT_NAMESPACE}" =~ "labor" ]]; then
                javaCmdOptions="${javaCmdOptions} -Dspring.profiles.active=pro"
        fi 
        # 布尔型变量校验
        for i in autoReuseImage; do
                if [ -z "`echo ${!i} | grep -E '^(true|false)$'`" ]; then
                        echo "[ERROR] 属性 ops.${i} 设置错误。取值范围应为：true、false"
                        exit 1
                fi
        done
	# 应用端口校验
	checkPort
}

# 用途：获取Html应用专用的环境变量
function getHtmlEnv() {
	# 获取apollo中的配置
	nodejsVersion=$(echo ${commonConfig} | jq -r '.["ops.nodejsVersion"]')
	nodejsBuildCommand=$(echo ${commonConfig} | jq -r '.["ops.nodejsBuildCommand"]')
        htmlPackageDirectory=$(echo ${commonConfig} | jq -r '.["ops.htmlPackageDirectory"]')
        # 前端项目不启用镜像复用功能
	autoReuseImage="false"

        # 应用端口
        appPort=80
        # 基础镜像
        baseHtmlImage="${repoAddress}/library/nginx:x1.12.0"
	# node.js版本校验
        case "${nodejsVersion}" in
        	"8.1.2")
                        export PATH=/opt/node/v8.1.2/bin:$PATH
                        ;;
        	"8.11.4")
                        export PATH=/opt/node/v8.11.4/bin:$PATH
                        ;;
        	"12.1.0")
                        export PATH=/opt/node/v12.1.0/bin:$PATH
                        ;;
        	"12.13.1")
                        export PATH=/opt/node/v12.13.1/bin:$PATH
                        ;;
        	"14.18.2")
                        export PATH=/opt/node/v14.18.2/bin:$PATH
                        ;;
        	"16.13.1")
                        export PATH=/opt/node/v16.13.1/bin:$PATH
                        ;;
        	*)
                        echo "[ERROR] 错误的node.js版本号"
                        exit 1
                        ;;
        esac
}

# 用途：获取Python应用专用的环境变量
function getPythonEnv() {
        # 获取apollo中的配置
	autoReuseImage=$(echo ${commonConfig} | jq -r '.["ops.autoReuseImage"]')
	appHealthUri=$(echo ${commonConfig} | jq -r '.["ops.appHealthUri"]')
	filebeatConfigMap=$(echo ${commonConfig} | jq -r '.["ops.filebeatConfigMap"]')
	appPort=$(echo ${commonConfig} | jq -r '.["ops.appPort"]')
	logIndex=$(echo ${commonConfig} | jq -r '.["ops.logIndex"]')
	pyBuildCommand=$(echo ${commonConfig} | jq -r '.["ops.pyBuildCommand"]')
	pyStartCommand=$(echo ${commonConfig} | jq -r '.["ops.pyStartCommand"]')

	# python版本
	pythonVersion='3.6'
	# 针对特殊项目设置pythonVersion版本
        if [[ "${CI_PROJECT_NAME}" =~ "akira-intelligent-center" ]];then
                pythonVersion='3.12'
        fi
	if [[ "${CI_PROJECT_NAME}" =~ "fitzgerald-python-toolkit" ]];then
		pythonVersion='3.11.9'
	fi
        # 基础镜像
        baseImage="${repoAddress}/library/python:${pythonVersion}"
        # 应用基础镜像
        baseTag='base'
        baseAppImage="${repoAddress}/library/${appId}:${baseTag}"
        # 应用镜像
        appImage="${repoAddress}/library/${appId}:${imageTag}"
        # 应用端口校验
	checkPort
}

# 用途：应用端口校验
function checkPort() {
        if [ "${appPort}" == "null" ]; then
                appConfig=$(curl -s http://config.${currentEnv}.bdata.api.example.com/configs/${appId}/default/application |jq -r '.configurations')
                serverPort=$(echo ${appConfig} | jq -r '.["server.port"]')
                if [ "${serverPort}" != "null" ]; then
                        appPort=${serverPort}
                else
                        echo "[ERROR] 请设置ops.appPort或server.port属性"
                        exit 1
                fi
        fi
}

# 用途：检查特定镜像是否存在
# 参数：镜像标签
function checkImageStatus(){
	imageTagName=$1
	headerData=$(curl -v -s https://${repoAddress}/v2/library/${appId}/tags/list 2>&1 |grep "Www-Authenticate")
  	headerRealm=$(echo ${headerData}|awk -F'"' '{print $2}')
  	headerService=$(echo ${headerData}|awk -F'"' '{print $4}')
  	headerScope=$(echo ${headerData}|awk -F'"' '{print $6}')
  	username="CHANGE_ME_REGISTRY_USER"
  	password="CHANGE_ME_REGISTRY_PASSWORD"

  	accessToken=$(curl -s -u clientId:clientSecret -X POST -d "username=${username}&password=${password}&service=${headerService}&scope=${headerScope}" ${headerRealm} | python -m json.tool|grep access_token|awk -F'"' '{print $4}')
	data=$(curl -s -u clientId:clientSecret -H "Accept: application/vnd.docker.distribution.manifest.v2+json" -H "Authorization: Bearer ${accessToken}" https://${repoAddress}/v2/library/${appId}/tags/list)
	if echo "$data"|grep -q "\"${imageTagName}\"";then
		echo "200"
	else
		echo "404"
	fi
}

# 用途：镜像构建
# 参数：完整镜像名称
function buildImage() {
	fullImageName="$1"
        echo "[INFO] 开始执行应用镜像构建"
        docker build \
        --label "org.opencontainers.image.authors=${GITLAB_USER_EMAIL}" \
        --label "org.opencontainers.image.source=${CI_PROJECT_URL}" \
        -t ${fullImageName} .
        if [ $? != 0 ];then
                echo "[ERROR] 应用镜像构建失败"
                exit 1
        fi
        echo "[INFO] 镜像构建完成，推送镜像到镜像仓库"
        docker push ${fullImageName}
	imagesToRemove=$(docker images | grep "/${appId}" | awk '{print $1":"$2}')
	if [ -n "${imagesToRemove}" ]; then
		docker rmi ${imagesToRemove} 2>&1 >> /dev/null
	fi
}

# 用途：重用应用镜像
# 返回值：0 代表发现可重用镜像，1 代表未发现可重用镜像
function reuseImage() {
        # 检查当前环境是否存在镜像
        imageStatus=$(checkImageStatus "${imageTag}")
        if [ "${imageStatus}" == "200" ]; then
        	echo "[INFO] 使用现有镜像：${repoAddress}/library/${appId}:${imageTag}"
		return 0
	fi
	return 1
}

# 用途：java应用构建(maven编译和生成镜像)
function javaBuild() {
        echo "[INFO] 使用版本：java ${javaVersion}"
	if [ `ls ${appSubDir}/target/*.jar 2> /dev/null | wc -l` != 0 ]; then
		echo "[INFO] 发现jar包，跳过maven构建阶段"
	else
		echo "[INFO] 使用版本：maven ${mavenVersion}"
		echo "[INFO] 构建命令：${mavenBuildCommand}"
        	echo "[INFO] 开始执行maven构建"
        	eval ${mavenBuildCommand}
		if [ $? != "0" ]; then
			echo "[ERROR] maven编译失败"
			exit 1
		fi
	fi
	echo "[INFO] 应用启动命令：java ${javaCmdOptions} -jar /app/app.jar"
	if [ -f "${appSubDir}/Dockerfile" ]; then
		echo "[INFO] 使用代码库中现有的Dockerfile"
		cd ${appSubDir}
	else
		echo "[INFO] 生成Dockerfile"
		cat > Dockerfile <<EOF
		FROM ${baseJavaImage}
		COPY ${appSubDir}/target/*.jar /app/app.jar
		CMD java \${JAVA_OPTS} -jar /app/app.jar
EOF
	fi
	buildImage "${repoAddress}/library/${appId}:${imageTag}"
	cd ${CI_PROJECT_DIR}
}

# 用途：准备java应用镜像
function prepareJavaImage() {
	if [ "${autoReuseImage}" == "true" -a "${supportApollo}" == "true" ]; then
		reuseImage
		if [ $? != 0 ]; then
			javaBuild
		fi
	else
		javaBuild
	fi
}

# 用途：准备html应用镜像
function HtmlBuild() {
        echo "[INFO] 使用版本：node.js ${nodejsVersion}"
        echo "[INFO] 构建命令：${nodejsBuildCommand}"
        echo "[INFO] 开始执行构建"
        eval ${nodejsBuildCommand}
	if [ $? != '0' ]; then
		echo '[ERROR] 应用编译失败'
		exit 1
	fi
	for i in ${htmlPackageDirectory}
	do
		if [ ! -e "${i}" ]; then
			echo "[ERROR] 文件/目录 \"${i}\" 不存在"
			exit 1
		fi
	done
	# 根据要打包的文件(或目录)是一个还是多个分情况处理
	if [ -n "`echo ${htmlPackageDirectory} | grep -E '^(\s)*(\S)+(\s)*$'`" ]; then 
		htmlResource=${htmlPackageDirectory}
	else
		rm -rf htmlResourceTmpDir
		mkdir htmlResourceTmpDir
		mv ${htmlPackageDirectory} htmlResourceTmpDir
		htmlResource='htmlResourceTmpDir'
	fi
	# 根据URI路径是否为/来分情况处理
	if [ "${appDomainReverseProxyUri}" == "/" ]; then
		cat > nginx.default.conf <<EOF
		server {
		    listen       80;
		    server_name  localhost;
		    root   /usr/share/nginx/html;
		    index  index.html index.htm;
		    location / {
		        try_files \$uri /index.html;
		    }
		}
EOF
	else
		cat > nginx.default.conf <<EOF
		server {
		        listen   80;
		        server_name  localhost;
		        index  index.html index.htm;
		
		        location / {
		                root   /usr/share/nginx/html;
		                return 200;
		        }
		        location ${appDomainReverseProxyUri} {
		                alias /usr/share/nginx/html/;
		                try_files \$uri ${appDomainReverseProxyUri}/index.html;
		        }
		}
EOF
	fi
        if [ -f "Dockerfile" ]; then
                echo "[INFO] 使用代码库中现有的Dockerfile"
        else
                echo "[INFO] 生成Dockerfile"
		cat > Dockerfile <<EOF
		FROM ${baseHtmlImage}
		COPY nginx.default.conf /etc/nginx/conf.d/default.conf
		COPY ${htmlResource} /usr/share/nginx/html/
EOF
	fi
	buildImage "${repoAddress}/library/${appId}:${imageTag}"
}

# 用途：准备html应用镜像
function prepareHtmlImage() {
        if [ "${autoReuseImage}" == "true" ]; then
                reuseImage
                if [ $? != 0 ]; then
                        HtmlBuild
                fi
        else
                HtmlBuild
        fi
}

# 用途：python应用构建(生成镜像)
function pythonBuild() {
	# 若代码库中存在Dockerfile，则直接构建应用镜像
        if [ -f "Dockerfile" ]; then
                echo "[INFO] 跳过基础镜像检查，忽略apollo中设置的编译和运行命令，使用代码库中现有的Dockerfile"
                buildImage "${appImage}"
		return 0
	fi
	# 检查是否存在应用基础镜像。若存在，直接生成应用镜像；若不存在，则生成应用基础镜像，再将其重置为应用镜像。
        imageStatus=$(checkImageStatus "${baseTag}")
        if [ "${imageStatus}" == "200" ]; then
                echo "[INFO] 使用现有应用基础镜像 ${baseAppImage}"
                echo "[INFO] 自动生成Dockerfile"
                cat > Dockerfile <<EOF
                        FROM ${baseAppImage}
                        WORKDIR /app/
                        COPY . /app/
                        RUN ${pyBuildCommand}
EOF
        	cat Dockerfile
		echo "[INFO] 开始生成应用镜像 ${appImage}"
        	buildImage "${appImage}"
		return 0
	fi
	echo "[INFO] 使用版本：python ${pythonVersion}"
	echo "[INFO] 自动生成Dockerfile"
	cat > Dockerfile <<EOF
        	FROM ${baseImage}
        	WORKDIR /app/
        	COPY . /app/
        	RUN mkdir -p /app/logs/app/ && ${pyBuildCommand}
EOF
        cat Dockerfile
	echo "[INFO] 开始生成应用基础镜像 ${baseAppImage}"
        buildImage "${baseAppImage}"
	echo "[INFO] 将应用基础镜像转置为应用镜像 ${baseAppImage} --> ${appImage}"
        docker tag ${baseAppImage} ${appImage}
        docker push ${appImage}
        docker rmi ${appImage}
}

# 用途：准备python应用镜像
function preparePythonImage() {
        if [ "${autoReuseImage}" == "true" ]; then
                reuseImage
                if [ $? != 0 ]; then
                        pythonBuild
                fi
        else
                pythonBuild
        fi
}

# 用途：k8s java应用部署模板
function k8sJavaDeployment() {
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${appId}.${currentEnv}
  namespace: ${currentEnv}
spec:
  replicas: ${k8sReplicas}
  strategy:
    type: ${k8sUpdateStrategy}
  selector:
    matchLabels:
      app: ${appId}
  template:
    metadata:
      labels:
        app: ${appId}
        notfixedvalue: ${notFixedValue}
    spec:
      terminationGracePeriodSeconds: 180
      restartPolicy: ${k8sRestartPolicy}
      containers:
      - name: consul-agent
        image: ${repoAddress}/library/consul:${consulVersion}
        ports:
        - containerPort: 8500
        env:
        - name: CONSUL_OPTS
          value: "-datacenter=${consulDatacenter} -retry-join=consul1.${consulCluster}.server.example.com -retry-join=consul2.${consulCluster}.server.example.com -retry-join=consul3.${consulCluster}.server.example.com"
      - name: filebeat
        image: ${repoAddress}/library/filebeat:7.2.0
        env:
        - name: ENV
          value: "${currentEnv}"
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: LOGTYPE
          value: "${logIndex}"
        volumeMounts:
        - name: logdir
          mountPath: /app/logs
        - name: filebeat-config
          mountPath: "/etc/filebeat/filebeat.yml"
          subPath: filebeat.yml
      - name: ${appId}
        image: ${repoAddress}/library/${appId}:${imageTag}
        imagePullPolicy: Always
        ports:
        - containerPort: ${appPort}
        resources:
          limits:
            cpu: ${appCpuLimit}
            memory: ${containerMaxMemory}Mi
          requests:
            cpu: 0.1
            memory: ${containerMinMemory}Mi
        env:
        - name: ENV
          value: "${currentEnv}"
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: JAVA_OPTS
          value: "${javaCmdOptions}"
        lifecycle:
          preStop:
            exec:
              command: ${preStopCommand}
        livenessProbe:
          httpGet:
            path: ${appHealthUri}
            port: ${appPort}
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 3
          successThreshold: 1
          failureThreshold: 18
        readinessProbe:
          httpGet:
            path: ${appHealthUri}
            port: ${appPort}
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 3
          successThreshold: 1
          failureThreshold: 18
        volumeMounts:
        - name: logdir
          mountPath: /app/logs
$(k8sGenerateVolumesInfo 'volumeMounts')
      volumes:
      - name: logdir
        emptyDir: {}
      - name: filebeat-config
        configMap:
          name: ${filebeatConfigMap}
$(k8sGenerateVolumesInfo 'volumes')
EOF
if [ $? != "0" ]; then
	echo "[ERROR] Deployment执行出错"
	exit 1
fi
}

# 用途：k8s html应用部署模板
function k8sHtmlDeployment(){
kubectl apply -f - <<EOF
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: ${appId}.${currentEnv}
  namespace: ${currentEnv}
spec:
  replicas: ${k8sReplicas}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
  selector:
    matchLabels:
      app: ${appId} 
  template:
    metadata:
      labels:
        app: ${appId}
        notfixedvalue: ${notFixedValue}
    spec:
      terminationGracePeriodSeconds: 60
      restartPolicy: ${k8sRestartPolicy}
      containers:
      - name: ${appId}
        image: ${repoAddress}/library/${appId}:${imageTag}
        imagePullPolicy: Always
        ports:
        - containerPort: ${appPort}
        resources:
          limits:
            cpu: ${appCpuLimit}
            memory: ${appMemoryLimit}Mi
          requests:
            cpu: 0
            memory: 0
        livenessProbe:
          httpGet:
            path: /
            port: ${appPort}
          initialDelaySeconds: 5
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /
            port: ${appPort}
          initialDelaySeconds: 5
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
EOF
if [ $? != "0" ]; then
        echo "[ERROR] Deployment执行出错"
        exit 1
fi
}

# 用途：k8s python应用部署模板
function k8sPythonDeployment() {
kubectl apply -f - <<EOF
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: ${appId}.${currentEnv}
  namespace: ${currentEnv}
spec:
  replicas: ${k8sReplicas}
  strategy:
    type: ${k8sUpdateStrategy}
  selector:
    matchLabels:
      app: ${appId} 
  template:
    metadata:
      labels:
        app: ${appId}
        notfixedvalue: ${notFixedValue}
    spec:
      terminationGracePeriodSeconds: 60
      containers:
      - name: filebeat
        image: ${repoAddress}/library/filebeat:7.2.0
        env:
        - name: ENV
          value: "${currentEnv}"
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: LOGTYPE
          value: "${logIndex}"
        volumeMounts:
        - name: logdir
          mountPath: /app/logs
        - name: filebeat-config
          mountPath: "/etc/filebeat/filebeat.yml"
          subPath: filebeat.yml
      - name: ${appId}
        image: ${appImage}
        imagePullPolicy: Always
        command: ["/bin/sh", "-c", "${pyStartCommand}"]
        ports:
        - containerPort: ${appPort}
        resources:
          limits:
            cpu: ${appCpuLimit}
            memory: ${appMemoryLimit}Mi
          requests:
            cpu: 0
            memory: 0
        env:
        - name: RUN_ENV
          value: "${currentEnv}"
        - name: APOLLO_CONFIG_URL
          value: "config.${currentEnv}.bdata.api.example.com"
        livenessProbe:
          httpGet:
            path: ${appHealthUri}
            port: ${appPort}
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 3
          successThreshold: 1
          failureThreshold: 18
        readinessProbe:
          httpGet:
            path: ${appHealthUri}
            port: ${appPort}
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 3
          successThreshold: 1
          failureThreshold: 18
        volumeMounts:
        - name: logdir
          mountPath: /app/logs
$(k8sGenerateVolumesInfo 'volumeMounts')
      volumes:
      - name: logdir
        emptyDir: {}
      - name: filebeat-config
        configMap:
          name: ${filebeatConfigMap}
$(k8sGenerateVolumesInfo 'volumes')
      tolerations:
      - key: "GPU"
        operator: "Equal"
        value: "${k8sGPU}"
        effect: "NoSchedule"
EOF
if [ $? != "0" ]; then
        echo "[ERROR] Deployment执行出错"
        exit 1
fi
}

# 用途：k8s service模板
function k8sService() {
kubectl apply -f - <<EOF
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
if [ $? != "0" ]; then
        echo "[ERROR] Service执行出错"
        exit 1
fi
}

# 用途：k8s ingress模板
function k8sIngress() {
kubectl apply -f - <<EOF
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: ${ingressName}
  namespace: ${currentEnv}
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
  - host: ${domain}
    http:
      paths:
      - path: ${appDomainReverseProxyUri}
        backend:
          serviceName: ${appId}
          servicePort: ${appPort}
EOF
if [ $? != "0" ]; then
        echo "[ERROR] Ingress执行出错"
        exit 1
fi
}

# 用途：k8s 添加PVC
function k8sPersistentVolumeClaim() {
kubectl apply -f - <<EOF
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: data-volume-${appId}
  namespace: ${currentEnv}
  annotations:
    volume.beta.kubernetes.io/storage-class: "${k8sStorageClass}"
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: ${persistentStorageSize}Gi
EOF
if [ $? != "0" ]; then
        echo "[ERROR] PersistentVolumeClaim执行出错"
        exit 1
fi
}

# 用途：k8s输出存储卷挂载信息
function k8sGenerateVolumesInfo(){
if [ "$1" = "volumes" -a "${persistentStorage}" = "true" ];then
cat <<EOF
      - name: data-volume
        persistentVolumeClaim:
          claimName: data-volume-${appId}
EOF
elif [ "$1" = "volumeMounts" -a "${persistentStorage}" = "true" ];then
cat <<EOF
        - name: data-volume
          mountPath: ${persistentStoragePath}
EOF
fi
}

# 用途：应用失败日志输出
function appFailLog() {
	if [ ${appType} == "java" ];then
		for i in {1..6};do echo " " ;done
		echo "[INFO] 应用部署失败，请查看以下应用启动日志"
		# 应用失败数量
		failNumber=`kubectl get pods -n ${currentEnv} |grep -i "^${appId}\.${currentEnv}"|grep "2/3" |wc -l`
		if [ ${failNumber} -eq 1 ];then
			appPodName=`kubectl get pods -n ${currentEnv} |grep -i "^${appId}\.${currentEnv}"|grep "2/3"|awk '{print $1}'`
			kubectl logs -f --tail 300 ${appPodName} -c  ${appId} -n ${currentEnv}
		else
			appPodName=`kubectl get pod -n ${currentEnv} --sort-by='{.metadata.creationTimestamp}' |grep -i "^${appId}\.${currentEnv}"|tail -n 1|awk '{print $1}'`
			kubectl logs -f --tail 300 ${appPodName} -c  ${appId} -n ${currentEnv}
		fi 
		echo "[INFO] 应用部署失败，请查看以上应用启动日志定位问题"
	fi
	if [ ${appType} == "html" ];then
		echo "[INFO] 应用部署失败，请查看应用启动日志定位问题"
	fi
	if [ ${appType} == "python" ];then
		echo "[INFO] 应用部署失败，请查看应用启动日志定位问题"
	fi
}

#用途：钉钉发送告警，针对阿里云 tag
########编写钉钉函数，调用。发送MD语法信息
function Send_ding_Success() {
    #用途： 获取当前脚本执行结束后的时间，用于计算基本执行的时间
    endTime=`date +%Y%m%d-%H:%M:%S`
    endTime_s=`date +%s`
    sumTime=$[ $endTime_s - $startTime_s ]
    # 应用ID
    if [ x${APP_ID} == x ]; then
	appId=${CI_PROJECT_NAME}
    else
	appId=${CI_PROJECT_NAME}_${APP_ID}
    fi
  
    #echo ${CI_ENVIRONMENT_NAME}
    #定义发送地址
    webhook_url="https://oapi.dingtalk.com/robot/send?access_token=CHANGE_ME_DINGTALK_TOKEN"
    #获取gitlab的变量  环境 $CI_JOB_STAGE  项目名称 CI_PROJECT_NAME   PIPELINE  CI_PIPELINE_ID     运行id  CI_JOB_ID
    #PIPELINE对应的id和url   CI_PIPELINE_ID         CI_PIPELINE_URL 
    #项目名称       CI_PROJECT_NAME                CI_PROJECT_URL
    #运行id         CI_JOB_ID                      CI_JOB_URL
    #if [ "${CI_ENVIRONMENT_NAME}" = "aliyun" ];then
        curl -ks -m 2 "${webhook_url}" \
            -H 'Content-Type: application/json;charset=utf-8' -d "{ 
    'msgtype': 'actionCard',
    'actionCard': {
        'title':'Gitlab持续交付信息',
        'text': '**<font color="#02b340"> ⚠️【Gitlab交付信息】</font>** \n\n\n\n **<font color="#02b340"> 发版环境: </font>**  **生产阿里云** \n\n **<font color="#02b340">项目名称:</font>**  **${appId}** \n\n **<font color="#02b340"> 项目标签: </font>**  **${CI_COMMIT_REF_NAME}**  \n\n  **<font color="#02b340">流水线_ID:</font>**   **${CI_PIPELINE_ID}**  \n\n **<font color="#02b340">JOB运行_ID:</font>**  **${CI_JOB_ID}** \n\n  **<font color="#02b340">运行结果:</font>**  **Success**  \n\n  **<font color="#02b340">运行时间:</font>**  **${sumTime} S**  \n\n  **<font color="#02b340">发布人: </font>**  **${GITLAB_USER_LOGIN}**',
        'singleTitle': '查看详情',
        'singleURL': 'dingtalk://dingtalkclient/page/link?url=${CI_JOB_URL##/?}&pc_slide=false'
        } 
    }"
   # fi
}

# 用途：主函数
function main() {
	getAppType
	getCommonEnv
	case ${appType} in
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
        # 执行PersistentVolumeClaim
        if [ "${persistentStorage}" = "true" ];then
          echo "[INFO] 启用持久化存储：true"
          echo "[INFO] 存储卷大小：${persistentStorageSize}G"
          echo "[INFO] 存储卷挂载路径：${persistentStoragePath}"
          k8sPersistentVolumeClaim
        fi
	# 执行Service和Ingress
	if [ "${appDomain}" != "null" ];then
  		k8sService
		i=0
		for domain in ${appDomain}; do
			let "i = i + 1"
			if [ $i == 1 ]; then
				ingressName=${appId}
			else
				ingressName="${appId}-${i}"
			fi
  			k8sIngress
		done
	fi
	echo "[INFO] 追踪应用部署状态 . . ."
	kubectl rollout status deployments ${appId}.${currentEnv} -n ${currentEnv} --timeout=4m
	if [ $? != "0" ]; then
                appFailLog
		exit 1
	fi
        echo "[INFO] 发布人: ${GITLAB_USER_LOGIN} "
        #Send_ding_Success
}

main

