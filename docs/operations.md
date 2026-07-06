# Prometheus
- job_name: 'rq_exporter'
-    static_configs:
-      - targets: ['rq_exporter:9121']
+ Add the RQ exporter scrape to infra/prometheus/prometheus.yml and ensure Grafana is provisioned with a Prometheus datasource and an initial dashboard at infra/grafana/dashboards/map_dashboard.json.
