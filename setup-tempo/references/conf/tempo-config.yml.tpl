# Tempo 配置说明：
# - Resource Attributes（如 deployment.environment）由 OTel Collector 注入，Tempo 原生保留，无需配置
# - TraceQL 可直接查询：{resource.deployment.environment="fat"}
# - 环境标识注入链路：Spring Boot → OTel Collector → Tempo

server:
  http_listen_port: 3200

# single-binary 模式 memberlist 显式声明（避免默认 ring 警告日志）
memberlist:
  bind_addr: ["127.0.0.1"]
  join_members: []

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: "0.0.0.0:4317"
        http:
          endpoint: "0.0.0.0:4318"
    zipkin:
      endpoint: "0.0.0.0:9411"

ingester:
  max_block_duration: 5m

compactor:
  compaction:
    block_retention: ${TEMPO_RETENTION}

metrics_generator:
  registry:
    external_labels:
      source: tempo
      cluster: tech-stack
  # 把 trace 的 deployment.environment resource attribute 作为 service-graph/span-metrics 维度
  # nonprod 域 4 环境（dev/sit/fat/uat）共用 Tempo 时按环境拆分指标，避免 service-graph 拓扑混淆
  processor:
    service_graphs:
      dimensions: [deployment_environment]
    span_metrics:
      dimensions: [deployment_environment]
  storage:
    path: /var/tempo/generator/wal
    remote_write:
      - url: http://${PROMETHEUS_HOST}:${PROMETHEUS_PORT}/api/v1/write
        send_exemplars: true

storage:
  trace:
    backend: local
    wal:
      path: /var/tempo/wal
    local:
      path: /var/tempo/blocks

overrides:
  defaults:
    metrics_generator:
      processors: [service-graphs, span-metrics]
