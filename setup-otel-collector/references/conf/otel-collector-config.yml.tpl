receivers:
  otlp:
    protocols:
      grpc:
        endpoint: "0.0.0.0:4317"
      http:
        endpoint: "0.0.0.0:4318"

processors:
  batch:
    send_batch_size: 1024
    timeout: 5s
  memory_limiter:
    check_interval: 5s
    limit_mib: 400
    spike_limit_mib: 100
  resource:
    attributes:
      # 环境标识注入（关键设计）
      # - action: insert 表示只在数据中不存在该属性时才插入，不会覆盖应用传来的值
      # - 应用通过 OTEL_RESOURCE_ATTRIBUTES=deployment.environment={env} 传入具体环境（dev/sit/fat/uat/prod）
      # - DEPLOYMENT_ENV 是域级标识（nonprod/prod），仅作为兜底值
      # - 例如：应用传 deployment.environment=fat，Collector 的 insert 不会覆盖，最终 Tempo/Loki 收到正确的 fat 标签
      - key: deployment.environment
        value: ${DEPLOYMENT_ENV}
        action: insert

exporters:
  otlp/tempo:
    endpoint: "${TEMPO_HOST}:${TEMPO_GRPC_PORT}"
    tls:
      insecure: true
  otlphttp/loki:
    endpoint: "http://${LOKI_HOST}:${LOKI_PORT}/otlp"

extensions:
  health_check:
    endpoint: "0.0.0.0:13133"

service:
  extensions: [health_check]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch, resource]
      exporters: [otlp/tempo]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch, resource]
      exporters: [otlphttp/loki]
  telemetry:
    logs:
      level: info
    metrics:
      # Collector 自身运行指标暴露端口，供 Prometheus 静态抓取
      # 业务应用 Metrics 不走 OTLP 推送，由 Prometheus 直接拉取 /actuator/prometheus
      address: "0.0.0.0:8888"
