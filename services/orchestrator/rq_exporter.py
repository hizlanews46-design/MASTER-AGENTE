#!/usr/bin/env python3
import time
from prometheus_client import Gauge, start_http_server
import redis
import os

REDIS_URL = os.environ.get('REDIS_URL', 'redis://redis:6379/0')
PORT = int(os.environ.get('RQ_EXPORTER_PORT', '9121'))

q_gauge = Gauge('rq_queue_jobs', 'Number of jobs in RQ queue', ['queue'])

r = redis.from_url(REDIS_URL)

def collect_and_set():
    # RQ stores queues as redis lists named rq:queue:<name>
    # We'll check the 'default' queue plus keys matching pattern
    try:
        queues = ['default']
        for q in queues:
            key = f"rq:queue:{q}"
            try:
                length = r.llen(key)
            except Exception:
                length = 0
            q_gauge.labels(queue=q).set(length)
    except Exception as e:
        print('rq_exporter error:', e)

if __name__ == '__main__':
    start_http_server(PORT)
    print(f'rq_exporter listening on {PORT} and scraping {REDIS_URL}')
    while True:
        collect_and_set()
        time.sleep(5)
