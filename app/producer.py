from flask import Flask, request, jsonify
import redis
import time
import socket

app = Flask(__name__)
# Connect to Redis. In our setup, Redis runs on node1.
r = redis.Redis(host='node1', port=6379, db=0)

@app.route('/')
def index():
    return jsonify({
        "status": "online",
        "service": "producer",
        "hostname": socket.gethostname()
    })

@app.route('/enqueue', methods=['GET', 'POST'])
def enqueue():
    task_id = request.args.get('task', f"task_{int(time.time())}")
    r.lpush('task_queue', task_id)
    return jsonify({
        "message": f"Task '{task_id}' enqueued successfully",
        "queue_length": r.llen('task_queue')
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
