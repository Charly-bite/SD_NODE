import redis
import time
import socket
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] (%(hostname)s) %(message)s')
hostname = socket.gethostname()

logger = logging.getLogger(__name__)
logger = logging.LoggerAdapter(logger, {'hostname': hostname})

# Connect to Redis running on node1
r = redis.Redis(host='node1', port=6379, db=0)

def worker():
    logger.info("Worker started, waiting for tasks...")
    while True:
        try:
            # Block and wait for a task from 'task_queue'
            task = r.brpop('task_queue', timeout=5)
            if task:
                queue_name, task_id = task
                task_id = task_id.decode('utf-8')
                logger.info(f"Picked up task: {task_id}")
                
                # Simulate processing work
                time.sleep(2)
                
                logger.info(f"Finished processing task: {task_id}")
            else:
                pass # timeout, just loop back
        except redis.ConnectionError:
            logger.error("Could not connect to Redis. Retrying in 5s...")
            time.sleep(5)
        except Exception as e:
            logger.error(f"Error: {e}")
            time.sleep(1)

if __name__ == '__main__':
    worker()
