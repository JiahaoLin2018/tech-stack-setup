# Action: configure

将目标机器的 DNS 配置指向 dnsmasq 服务器。适用于无法控制路由器 DHCP 的场景，需逐台配置。

## 命令格式

```
/setup-dns configure --host <目标机器IP> --dns-server <dnsmasq机器IP> --user <user> [--password <pass>|--key <path>]
```

> - `--host`：**要配置 DNS 的目标机器**（不是 dnsmasq 所在机器）
> - `--dns-server`：dnsmasq 服务器的 IP（即此前 `start` 部署 dnsmasq 的目标机器 IP）

## 步骤

### 本地模式（HOST=localhost 或 127.0.0.1）

配置本机的 DNS 指向 dnsmasq。

> **注意**：本地模式仅**展示配置命令**供用户确认后手动执行，因为修改本机 DNS 需要 sudo 权限且影响全局网络，必须由用户主动操作。远程模式则通过 SSH 直接执行。

1. **校验 `--dns-server` 参数**：
   ```bash
   if [ -z "$DNS_SERVER_IP" ]; then
     echo "❌ 请通过 --dns-server <ip> 指定 dnsmasq 服务器 IP"
     echo "   例：/setup-dns configure --dns-server 192.168.1.10"
     exit 1
   fi
   ```

2. **检测操作系统和 DNS 管理方式**：

   **Linux（systemd-resolved）** — 推荐，支持条件转发：
   ```bash
   if systemctl is-active systemd-resolved > /dev/null 2>&1; then
     echo "检测到 systemd-resolved"
     echo ""
     echo "=== 推荐方式：条件转发（仅 *.renew.com 走 dnsmasq）==="
     echo "  sudo mkdir -p /etc/systemd/resolved.conf.d/"
     echo "  sudo tee /etc/systemd/resolved.conf.d/tech-stack-dns.conf <<EOF"
     echo "  [Resolve]"
     echo "  DNS=${DNS_SERVER_IP}"
     echo "  Domains=~renew.com"
     echo "  EOF"
     echo "  sudo systemctl restart systemd-resolved"
     echo ""
     echo "=== 备选方式：全局替换（所有域名走 dnsmasq）==="
     echo "  sudo systemctl stop systemd-resolved"
     echo "  sudo systemctl disable systemd-resolved"
     echo "  sudo rm /etc/resolv.conf"
     echo "  echo 'nameserver ${DNS_SERVER_IP}' | sudo tee /etc/resolv.conf"
     echo "  echo 'nameserver 114.114.114.114' | sudo tee -a /etc/resolv.conf"
   fi
   ```

   > **推荐条件转发的原因**：`Domains=~renew.com` 表示只将 `*.renew.com` 的查询发给 dnsmasq，其他域名仍走原 DNS，不影响公司内网域名解析。

   **Linux（NetworkManager，无 systemd-resolved）**：
   ```bash
   if command -v nmcli > /dev/null 2>&1 && ! systemctl is-active systemd-resolved > /dev/null 2>&1; then
     CONN=$(nmcli -t -f NAME con show --active | head -1)
     echo "检测到 NetworkManager（无 systemd-resolved），当前连接：$CONN"
     echo ""
     echo "=== 全局替换（NetworkManager 不支持客户端条件转发）==="
     echo "  sudo nmcli con mod \"$CONN\" ipv4.dns \"${DNS_SERVER_IP} 114.114.114.114\""
     echo "  sudo nmcli con up \"$CONN\""
   fi
   ```

   > **注意**：NetworkManager 不像 systemd-resolved 那样支持条件转发（指定域名走特定 DNS）。如果需要条件转发，请改用 systemd-resolved。

   **Linux（直接修改 resolv.conf）** — 最后备选：
   ```bash
   if ! systemctl is-active systemd-resolved > /dev/null 2>&1 && ! command -v nmcli > /dev/null 2>&1; then
     echo "未检测到 systemd-resolved 或 NetworkManager"
     echo ""
     echo "=== 全局替换（所有域名走 dnsmasq）==="
     echo "  echo 'nameserver ${DNS_SERVER_IP}' | sudo tee /etc/resolv.conf"
     echo "  echo 'nameserver 114.114.114.114' | sudo tee -a /etc/resolv.conf"
     echo ""
     echo "⚠️  注意：某些系统（如 Ubuntu）会在重启后覆盖 resolv.conf"
     echo "  建议优先使用 systemd-resolved 方式"
   fi
   ```

   **macOS** — 原生支持条件转发：
   ```bash
   echo "macOS 配置方式："
   echo ""
   echo "=== 推荐方式：条件转发（仅 *.renew.com 走 dnsmasq）==="
   echo "  sudo mkdir -p /etc/resolver/"
   echo "  echo 'nameserver ${DNS_SERVER_IP}' | sudo tee /etc/resolver/renew.com"
   echo ""
   echo "此方式仅将 *.renew.com 查询发给 dnsmasq，其他域名走系统默认 DNS。"
   echo ""
   echo "=== 备选方式：全局替换（系统偏好设置）==="
   echo "  系统偏好设置 → 网络 → 高级 → DNS → 添加 ${DNS_SERVER_IP}"
   ```

   **Windows** — 使用 NRPT 条件转发：
   ```powershell
   echo "Windows 配置方式："
   echo ""
   echo "=== 推荐方式：NRPT 条件转发（仅 *.renew.com 走 dnsmasq）==="
   echo "  # PowerShell（管理员）"
   echo "  Add-DnsClientNrptRule -Namespace '.renew.com' -NameServers '${DNS_SERVER_IP}'"
   echo "  # 验证规则"
   echo "  Get-DnsClientNrptRule"
   echo "  # 刷新缓存"
   echo "  Clear-DnsClientCache"
   echo ""
   echo "=== 备选方式：全局替换（所有域名走 dnsmasq）==="
   echo "  # 方式一：GUI 设置"
   echo "    1. 打开 设置 → 网络和 Internet → 以太网（或 Wi-Fi）"
   echo "    2. 点击 DNS 服务器分配 → 编辑"
   echo "    3. 选择'手动'"
   echo "    4. 首选 DNS：${DNS_SERVER_IP}"
   echo "    5. 备用 DNS：114.114.114.114"
   echo ""
   echo "  # 方式二：PowerShell（管理员）"
   echo "    Get-NetAdapter | Select-Object Name, Status"
   echo "    Set-DnsClientServerAddress -InterfaceAlias '以太网' -ServerAddresses ('${DNS_SERVER_IP}','114.114.114.114')"

   echo ""
   echo "⚠️  注意事项："
   echo "  - NRPT 条件转发不影响公司 DNS，推荐使用"
   echo "  - PowerShell 命令需要管理员权限"
   echo "  - 配置后需刷新 DNS 缓存：Clear-DnsClientCache"
   echo "  - 如果之前在 hosts 文件中配置了 *.renew.com，可删除相关条目（NRPT 优先级高于 hosts）"
   echo "  - hosts 文件路径：C:\Windows\System32\drivers\etc\hosts"
   echo "  - 删除 NRPT 规则：Remove-DnsClientNrptRule -Namespace '.renew.com'"
   ```

3. **验证配置生效**：
   ```bash
   # 测试 renew.com 域名（用泛解析覆盖的全局域名，避免依赖 hosts.lan 是否填好实际 IP）
   nslookup gitlab.renew.com 2>/dev/null && echo "✅ DNS 配置生效" || echo "❌ DNS 配置未生效"
   # 测试公网域名
   nslookup baidu.com 2>/dev/null && echo "✅ 公网解析正常" || echo "❌ 公网解析失败"
   ```

---

### 远程模式（HOST 为非本地 IP）

通过 SSH 在远程 Linux 机器上配置 DNS 指向 dnsmasq。

> **--user 要求**：远程模式会执行 `sudo systemctl restart` 等命令。`--user` 必须满足以下任一条件：
> - 是 `root`（默认，无需 sudo）
> - 是已配置 NOPASSWD sudo 的非 root 用户
>
> 普通用户 + 密码认证场景下 `sudo` 会等待 tty 输入密码导致会话挂起。

1. **校验 `--dns-server` 参数**：
   ```bash
   if [ -z "$DNS_SERVER_IP" ]; then
     echo "❌ 请通过 --dns-server <ip> 指定 dnsmasq 服务器 IP"
     exit 1
   fi
   ```

2. **测试 SSH 连通性 + sudo 可用性**：
   ```bash
   ssh ... "echo OK"
   # 非 root 用户额外检查 NOPASSWD sudo
   if [ "$USER" != "root" ]; then
     ssh ... "sudo -n true 2>/dev/null" || {
       echo "❌ 用户 $USER 无 NOPASSWD sudo 权限，远程模式无法继续"
       echo "   解决方案：使用 --user root，或在目标机器配置 NOPASSWD sudo"
       exit 1
     }
   fi
   ```

3. **检测远程 DNS 管理方式并配置**：
   ```bash
   # 检测是否使用 systemd-resolved
   HAS_RESOLVED=$(ssh ... "systemctl is-active systemd-resolved 2>/dev/null")

   if [ "$HAS_RESOLVED" = "active" ]; then
     echo "远程机器使用 systemd-resolved，配置条件转发..."
     ssh ... "sudo mkdir -p /etc/systemd/resolved.conf.d/ && \
       echo '[Resolve]' | sudo tee /etc/systemd/resolved.conf.d/tech-stack-dns.conf && \
       echo 'DNS=${DNS_SERVER_IP}' | sudo tee -a /etc/systemd/resolved.conf.d/tech-stack-dns.conf && \
       echo 'Domains=~renew.com' | sudo tee -a /etc/systemd/resolved.conf.d/tech-stack-dns.conf && \
       sudo systemctl restart systemd-resolved"
     echo "✅ 已配置 systemd-resolved 条件转发 *.renew.com → ${DNS_SERVER_IP}"
   else
     # 检测是否使用 NetworkManager
     HAS_NM=$(ssh ... "command -v nmcli > /dev/null 2>&1 && nmcli -t -f NAME con show --active | head -1")
     
     if [ -n "$HAS_NM" ]; then
       echo "远程机器使用 NetworkManager，配置全局替换..."
       ssh ... "sudo nmcli con mod \"$HAS_NM\" ipv4.dns \"${DNS_SERVER_IP} 114.114.114.114\" && \
         sudo nmcli con up \"$HAS_NM\""
       echo "✅ 已配置 NetworkManager DNS"
     else
       echo "远程机器无 systemd-resolved 或 NetworkManager，直接配置 resolv.conf..."
       ssh ... "echo 'nameserver ${DNS_SERVER_IP}' | sudo tee /etc/resolv.conf && \
         echo 'nameserver 114.114.114.114' | sudo tee -a /etc/resolv.conf"
       echo "✅ 已配置 resolv.conf"
     fi
   fi
   ```

4. **验证远程 DNS 配置**：
   ```bash
   # 用泛解析覆盖的全局域名验证（不依赖 hosts.lan 是否填好实际 IP）
   ssh ... "nslookup gitlab.renew.com 2>/dev/null && echo '✅ DNS 配置生效' || echo '❌ DNS 配置未生效'"
   ssh ... "nslookup baidu.com 2>/dev/null && echo '✅ 公网解析正常' || echo '❌ 公网解析失败'"
   ```

5. **展示结果**：
   ```
   ✅ 远程机器 $HOST 的 DNS 已配置完成！

   DNS 服务器：${DNS_SERVER_IP}
   配置方式：<systemd-resolved 条件转发 / NetworkManager 全局替换 / resolv.conf 直接配置>

   该机器现在可以通过域名访问所有基础设施服务：
     mysql-dev.renew.com（直连层）, grafana-nonprod-ui.renew.com（代理层）, gitlab.renew.com（全局唯一） ...
   ```
