from flask import Response, Flask, render_template, request, redirect
import requests
from config import LB_PUBLIC_IP
import json

app = Flask(__name__)


@app.route('/enqueue', methods=['PUT'])
def enqueue():
    if request.method == "PUT":
        data = request.get_data()
        iter = int(request.args.get("iterations"))
        res = requests.put(url=f"http://{LB_PUBLIC_IP}:5000/addJob?iterations={iter}", data=data)
        return Response(status=res.status_code)


@app.route('/pullCompleted', methods=['POST'])
def pullCompleted():
    if request.method == "POST":
        top = int(request.args.get('top'))
        respond = requests.post(f"http://{LB_PUBLIC_IP}:5000/pullCompleted?top={top}")
        return Response(mimetype='application/json', response=json.dumps(respond.json()), status=200)
