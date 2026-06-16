apiVersion: 1

datasources:
  # ==================== Prometheus ====================
  - name: Prometheus
    type: prometheus
    access: proxy
    uid: prometheus
    orgId: 1
    url: http://${PROMETHEUS_HOST}:${PROMETHEUS_PORT}
    isDefault: true
    editable: false
    jsonData:
      timeInterval: '15s'
      httpMethod: POST

  # ==================== Tempo ====================
  - name: Tempo
    type: tempo
    access: proxy
    uid: tempo
    orgId: 1
    url: http://${TEMPO_HOST}:${TEMPO_PORT}
    editable: false
    jsonData:
      # Trace → Logs 关联配置
      tracesToLogsV2:
        datasourceUid: loki
        filterByTraceID: true
        filterBySpanID: true
        spanStartTimeShift: '-1h'
        spanEndTimeShift: '1h'
      # Trace → Metrics 关联配置
      tracesToMetrics:
        datasourceUid: prometheus
      # Node Graph 显示配置
      nodeGraph:
        enabled: true
      # Service Map 配置
      serviceMap:
        datasourceUid: prometheus
      # TraceQL 搜索配置
      search:
        hide: false

  # ==================== Loki ====================
  - name: Loki
    type: loki
    access: proxy
    uid: loki
    orgId: 1
    url: http://${LOKI_HOST}:${LOKI_PORT}
    editable: false
    jsonData:
      maxLines: 1000
      # Log → Trace 关联配置
      derivedFields:
        - datasourceUid: tempo
          matcherRegex: '"traceId":"(\w+)"'
          name: TraceID
          url: '$${__value.raw}'
