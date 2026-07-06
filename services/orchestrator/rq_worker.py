from rq import Worker, Queue, Connection
from redis import Redis
import os

if __name__ == '__main__':
    redis_url = os.environ.get('REDIS_URL', 'redis://redis:6379/0')
    redis_conn = Redis.from_url(redis_url)
    with Connection(redis_conn):
        worker = Worker(['default'])
        worker.work()
