from prometheus_client import Counter

RUNS_CREATED = Counter('map_runs_created_total', 'Total runs created')
RUNS_FINISHED = Counter('map_runs_finished_total', 'Total runs finished')
