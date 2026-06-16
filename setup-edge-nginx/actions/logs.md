# Action: logs

查看 edge-nginx 日志。

## 参数解析

### Step 0：--env 参数解析（B 类契约）

从用户指令中提取 --env 参数：
- 若未传入 → 默认 `nonprod`
- 若值为 `nonprod` 或 `prod` → 正常执行
- 若值非法 → 报错退出

### 可选参数

- `--tail`：显示最后 N 行（默认 100）
- `--follow`：实时跟踪日志（-f）

## 日志来源

edge-nginx 有两类日志：

1. **容器日志** — stdout/stderr（docker logs）
2. **访问日志** — /var/log/nginx/access.log
3. **错误日志** — /var/log/nginx/error.log

## 查看日志

### 容器日志

```bash
# 最近 100 行
<SSH> docker logs --tail 100 tech-edge-nginx-${ENV}

# 实时跟踪
<SSH> docker logs -f --tail 100 tech-edge-nginx-${ENV}
```

### 访问日志

```bash
# 最近 100 条访问记录
<SSH> tail -100 /opt/tech-stack/edge-nginx-${ENV}/logs/access.log

# 实时跟踪
<SSH> tail -f /opt/tech-stack/edge-nginx-${ENV}/logs/access.log

# 过滤特定域名
<SSH> grep "demo.prod.web.renew.com" /opt/tech-stack/edge-nginx-${ENV}/logs/access.log | tail -50
```

### 错误日志

```bash
# 最近错误
<SSH> tail -100 /opt/tech-stack/edge-nginx-${ENV}/logs/error.log

# 过滤特定错误级别
<SSH> grep -E "\[error\]|\[crit\]" /opt/tech-stack/edge-nginx-${ENV}/logs/error.log | tail -50
```

## 日志格式

### 访问日志格式

```
$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" $request_time
```

示例：
```
192.168.1.100 - - [20/Apr/2026:10:30:00 +0800] "GET /api/health HTTP/1.1" 200 15 "-" "curl/7.68.0" 0.001
```

## 常用过滤命令

```bash
# 统计状态码分布
<SSH> awk '{print $9}' /opt/tech-stack/edge-nginx-${ENV}/logs/access.log | sort | uniq -c | sort -rn

# 统计访问量前 10 的 IP
<SSH> awk '{print $1}' /opt/tech-stack/edge-nginx-${ENV}/logs/access.log | sort | uniq -c | sort -rn | head -10

# 统计响应时间分布
<SSH> awk '{print $NF}' /opt/tech-stack/edge-nginx-${ENV}/logs/access.log | sort -n | awk '{sum+=$1; count++} END {print "avg:", sum/count, "total:", count}'

# 过滤 4xx/5xx 错误
<SSH> awk '$9 ~ /^[45]/' /opt/tech-stack/edge-nginx-${ENV}/logs/access.log | tail -50
```
