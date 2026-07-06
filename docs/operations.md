# RQ Dashboard access
- UI: http://<VM_IP>:9181 (rq-dashboard)

# RQ exporter metrics
- Prometheus endpoint: http://<VM_IP>:9121/metrics
+ RQ Dashboard UI: http://<VM_IP>:9181 (rq-dashboard)
+
+ RQ exporter metrics: http://<VM_IP>:9121/metrics
+  - Exposes prometheus metric `rq_queue_jobs{queue="default"}`
