# import hashlib
# import uuid
# from flask import Flask, request, jsonify
#
# app = Flask(__name__)
# work_queue = []
# completed_work = {}
#
#
# @app.route('/enqueue', methods=['PUT'])
# def enqueue_work():
#     iterations = int(request.args.get('iterations'))
#     data = request.data
#     work_id = str(uuid.uuid4())
#     work_queue.append((work_id, data, iterations))
#     return jsonify({'work_id': work_id})
#
#
# @app.route('/pullCompleted', methods=['POST'])
# def pull_completed_work():
#     top = int(request.args.get('top'))
#     completed = [(work_id, result) for work_id, result in completed_work.items()]
#     completed = sorted(completed, key=lambda x: x[0], reverse=True)[:top]
#     return jsonify({'completed_work': completed})
#
#
# def worker():
#     while True:
#         if work_queue:
#             work_id, data, iterations = work_queue.pop(0)
#             result = process_work(data, iterations)
#             completed_work[work_id] = result
#
#
# def process_work(data, iterations):
#     output = hashlib.sha512(data).digest()
#     for _ in range(iterations - 1):
#         output = hashlib.sha512(output).digest()
#     return output
#
#
# if __name__ == '__main__':
#     # Start two instances to handle the endpoints
#     app.run(host='0.0.0.0', port=8000)
#     app.run(host='0.0.0.0', port=8001)
#
#     # Start multiple worker nodes
#     for _ in range(5):
#         worker()
