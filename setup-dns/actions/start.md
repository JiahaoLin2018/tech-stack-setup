# Action: start

启动 dnsmasq DNS 服务（支持本地和远程两种部署模式）。

## 命令格式

```
/setup-dns start [--host <ip>] [--user <user>] [--password <pass>|--key <path>]
```

## 步骤

> **文件上传约束**：上传 docker-compose.yml 等含 `${VAR}` 变量引用的文件时，必须使用文件复制方式（`scp` 或 `sftp.put()`），禁止使用 Python 字符串写入（会导致 `${VAR}` 被吞掉变为空值）。详见 `references/deployment-principles.md` 前置准备第 6 节。

0. **--env 参数校验**（C 类：全局唯一，不接受 --env）：
   ```bash
   if [ -n "$ENV" ]; then
     echo "❌ setup-dns 是全局唯一服务（C 类），不接受 --env 参数。"
     echo "   请移除 --env 参数后重试。"
     exit 1
   fi
   ```

1. **检查本地 SSH 工具**：
   - 密码认证：检查 `sshpass` 是否已安装（`which sshpass`），未安装则提示：`brew install sshpass` (Mac) / `apt install sshpass` (Linux)
   - Key 认证：检查 key 文件存在且权限正确（`chmod 600 <key>`）

2. **测试 SSH 连通性**：
   ```bash
   # 密码认证
   sshpass -p "$PASS" ssh -p $SSH_PORT -o StrictHostKeyChecking=no -o ConnectTimeout=5 $USER@$HOST "echo OK"
   # Key 认证
   ssh -i "$KEY" -p $SSH_PORT -o StrictHostKeyChecking=no -o ConnectTimeout=5 $USER@$HOST "echo OK"
   ```

3. **检查/安装远程 Docker**：
   ```bash
   ssh ... "docker info > /dev/null 2>&1 || (curl -fsSL https://get.docker.com | sh && systemctl enable docker && systemctl start docker)"
   ```

4. **检查内核参数**（Docker 网络必需）：
   ```bash
   ssh ... "sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward 2>/dev/null"
   ```
   若任一参数不为 1，提示用户：
   ```
   ⚠️  目标机器 $HOST 缺少 Docker 网络所需内核参数（容器端口映射不可用）：
        net.bridge.bridge-nf-call-iptables / net.bridge.bridge-nf-call-ip6tables / net.ipv4.ip_forward

   请按 references/deployment-principles.md 前置准备章节配置后重试 /setup-dns start。
   ```
   **终止流程**，等待用户配置后重试。

5. **检查远程 53 端口**（dnsmasq 容器需独占 :53）：
   ```bash
   ssh ... "ss -tulnp 'sport = :53' 2>/dev/null"
   ```
   若有任何输出（LISTEN / UNCONN 行），说明端口已被占用，提示用户：
   ```
   ⚠️  目标机器 $HOST 的端口 :53 已被占用：

   <上述 ss 命令的完整输出（含进程名 / PID）>

   请先在目标机器上清理占用 :53 的服务后重试 /setup-dns start。
   ```
   **终止流程**，等待用户清理后重试。

6. **上传配置文件**（区分模板 vs 用户文件）：
   ```bash
   ssh ... "mkdir -p /opt/tech-stack/dns"

   # 模板文件：始终覆盖（skill 升级后远程能拿到最新版本）
   for f in docker-compose.yml .env.example; do
     scp ... ${CLAUDE_SKILL_DIR}/references/$f $USER@$HOST:/opt/tech-stack/dns/$f
   done

   # 用户文件：仅在不存在时上传，保护用户已填写的内容
   for f in hosts.lan; do
     ssh ... "test -f /opt/tech-stack/dns/$f" || scp ... ${CLAUDE_SKILL_DIR}/references/$f $USER@$HOST:/opt/tech-stack/dns/$f
   done
   ```

   > `dnsmasq.conf` 不在此处上传，由步骤 8 替换变量后单独上传。

7. **检查远程 .env 并校验关键字段**：
   ```bash
   ssh ... "test -f /opt/tech-stack/dns/.env"
   ```
   - 不存在 → 提示用户：
     ```
     ssh $USER@$HOST "cp /opt/tech-stack/dns/.env.example /opt/tech-stack/dns/.env && nano /opt/tech-stack/dns/.env"
     ```
     修改以下字段后重试：`DNS_WEB_PASSWORD`、`INFRA_NGINX_IP`（必改），`UPSTREAM_DNS_PRIMARY` / `UPSTREAM_DNS_SECONDARY`（可选，按所在地域调整）

   - 存在 → 校验关键字段未保留 `CHANGE_ME_*` 占位符：
     ```bash
     ssh ... "grep -E '^(DNS_WEB_PASSWORD|INFRA_NGINX_IP)=' /opt/tech-stack/dns/.env | grep CHANGE_ME"
     ```
     若有命中行，提示用户更新对应字段后重试。

8. **从远程 .env 读取变量，本地替换 dnsmasq.conf 后上传**（不修改原始模板）：
   ```python
   import os, re, subprocess, tempfile

   SSH_OPTS = ['-p', str(SSH_PORT), '-o', 'StrictHostKeyChecking=no']
   if KEY:
       SSH_BASE = ['ssh', '-i', KEY, *SSH_OPTS]
       SCP_BASE = ['scp', '-i', KEY, *SSH_OPTS]
   else:
       SSH_BASE = ['sshpass', '-p', PASS, 'ssh', *SSH_OPTS]
       SCP_BASE = ['sshpass', '-p', PASS, 'scp', *SSH_OPTS]

   def get_env(key):
       """从远程 .env 取值，剥离引号 / 行尾注释 / 首尾空白"""
       cmd = f"grep '^{key}=' /opt/tech-stack/dns/.env || true"
       result = subprocess.run(SSH_BASE + [f'{USER}@{HOST}', cmd], capture_output=True, text=True)
       line = result.stdout.strip()
       if not line:
           return ''
       value = line.split('=', 1)[1] if '=' in line else ''
       value = re.sub(r'\s+#.*$', '', value)         # 剥离行尾 # 注释
       value = value.strip().strip('"').strip("'")   # 剥离首尾空白和引号
       return value

   substitutions = {
       'INFRA_NGINX_IP':         get_env('INFRA_NGINX_IP'),
       'UPSTREAM_DNS_PRIMARY':   get_env('UPSTREAM_DNS_PRIMARY') or '114.114.114.114',
       'UPSTREAM_DNS_SECONDARY': get_env('UPSTREAM_DNS_SECONDARY') or '8.8.8.8',
   }

   if not substitutions['INFRA_NGINX_IP'] or 'CHANGE_ME' in substitutions['INFRA_NGINX_IP']:
       print("❌ 远程 .env 中 INFRA_NGINX_IP 未配置，请先按步骤 7 修改 .env")
       exit(1)

   with open(f'{CLAUDE_SKILL_DIR}/references/dnsmasq.conf') as f:
       content = f.read()
   for k, v in substitutions.items():
       content = content.replace(f'${{{k}}}', v)

   # 写入临时文件再 scp 上传，try/finally 保证清理
   tmp = tempfile.NamedTemporaryFile(mode='w', suffix='.conf', delete=False)
   try:
       tmp.write(content); tmp.close()
       subprocess.run(SCP_BASE + [tmp.name, f'{USER}@{HOST}:/opt/tech-stack/dns/dnsmasq.conf'], check=True)
   finally:
       os.unlink(tmp.name)
   ```

9. **检查远程 hosts.lan 是否已替换占位符**：
   ```bash
   ssh ... "grep -v '^#' /opt/tech-stack/dns/hosts.lan | grep -v '^$' | grep -v CHANGE_ME | head -3"
   ```
   若无有效记录（全是 CHANGE_ME 占位），提示用户编辑 hosts.lan 填入实际 IP 后重试。

10. **远程启动**：
    ```bash
    ssh ... "cd /opt/tech-stack/dns && docker compose up -d"
    ```

11. **等待健康检查**：
    ```bash
    ssh ... "docker inspect tech-dns --format='{{.State.Health.Status}}'"
    ```
    - 返回 `healthy` → 继续
    - 超时 → `ssh ... "docker logs tech-dns --tail 30"` 展示日志

12. **展示连接信息**（使用 $HOST 而非 localhost）：
    ```
    ✅ dnsmasq DNS 服务已部署至远程服务器！

    DNS 服务地址：$HOST:53
    Web 管理界面：http://$HOST:${DNS_WEB_PORT:-5380}

    下一步：在每台服务器上执行 configure 操作指向此 DNS：
      /setup-dns configure --host <目标机器IP> --dns-server $HOST --user <user> --key <key>

    注意：请确保防火墙已开放端口 53（TCP/UDP）和 ${DNS_WEB_PORT:-5380}
    ```

---

## 部署报告输出

> 部署完成后，必须在项目 `env/` 目录下生成或更新该服务的部署报告文件 `env/<service>.md`。

报告模板：

```markdown
# <服务名称> — 部署报告

| 项目 | 值 |
|------|-----|
| 部署日期 | YYYY-MM-DD |
| 目标机器 | <IP> |
| 部署目录 | /opt/tech-stack/<service>/ |
| 容器名称 | <container_name> |
| 镜像 | <image:tag> |
| 版本 | <version> |

## 端口

| 端口 | 用途 |
|------|------|
| <port> | <description> |

## 账号密码

| 用户 | 密码 | 权限 | 允许来源 |
|------|------|------|---------|
| <user> | <password> | <permissions> | <access_scope> |

## 连接方式

| 方式 | 地址 |
|------|------|
| <client_type> | <connection_string> |

## 备注

- <部署过程中的特殊配置或踩坑记录>
```

报告文件路径：`<project_root>/env/<service>.md`（如 `env/mysql.md`、`env/redis.md`）
