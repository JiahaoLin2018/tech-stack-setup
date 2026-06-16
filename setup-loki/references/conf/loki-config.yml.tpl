auth_enabled: ${LOKI_AUTH_ENABLED}

server:
  http_listen_port: 3100
  grpc_listen_port: ${LOKI_GRPC_PORT}
  log_level: ${LOKI_LOG_LEVEL}

common:
  instance_addr: 127.0.0.1
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

query_range:
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: ${LOKI_CACHE_MAX_SIZE_MB}

limits_config:
  retention_period: ${LOKI_RETENTION_PERIOD}
  ingestion_rate_mb: ${LOKI_INGESTION_RATE_MB}
  ingestion_burst_size_mb: ${LOKI_INGESTION_BURST_SIZE_MB}
  max_streams_per_user: ${LOKI_MAX_STREAMS_PER_USER}
  max_query_series: ${LOKI_MAX_QUERY_SERIES}
  allow_structured_metadata: true
  otlp_config:
    resource_attributes:
      attributes_config:
        - action: index_label
          attributes:
            - service.name
            - deployment.environment

schema_config:
  configs:
    - from: "2024-01-01"
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://${ALERTMANAGER_HOST}:${ALERTMANAGER_PORT}

compactor:
  working_directory: /loki/compactor
  compaction_interval: ${LOKI_COMPACTION_INTERVAL}
  retention_enabled: true
  retention_delete_delay: ${LOKI_RETENTION_DELETE_DELAY}
  retention_delete_worker_count: 150
  delete_request_store: filesystem
