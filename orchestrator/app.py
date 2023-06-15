from flask import Flask, Response, request
from datetime import datetime
import json
import threading
import time
import uuid
import boto3
from config import MAX_Q_TIME_SEC, PERIODIC_ITERATION, INSTANCE_TYPE, \
    PATH_TO_CONST_TXT, WORKER_AMI_ID, LB_PUBLIC_IP, USER_REGION

app = Flask(__name__)
work_queue = []
result_list = []
next_call = time.time()


@app.route('/pullCompleted', methods=['POST'])
def pullCompleted():
    if request.method == "POST":
        top = int(request.args.get('top'))
        slice_index = min(top, len(result_list))
        return Response(mimetype='application/json',
                        response=json.dumps({"result": result_list[:slice_index]}),
                        status=200)


@app.route('/get_result', methods=['PUT'])
def get_result():
    if request.method == "PUT":
        result_list.append({"job_id": request.json["job_id"], "result": request.json["result"]})


def read_from_txt(path):
    global const
    with open(path, "r") as f:
        lines = f.readlines()
        items = [line.replace('"', "").replace("\n", "") for line in lines if "=" in line]
        const = dict([element.split("=") for element in items])


def deploy_worker(app_path, exit_flag=True, min_count=1, max_count=1):
    user_data = f"""#!/bin/bash
                   cd {const["PROJ_NAME"]}
                   git pull
                   echo LB_PUBLIC_IP = f{LB_PUBLIC_IP} >> {const["WORKER_CONFIG"]}
                   echo EXIT_FLAG = {exit_flag} >> {const["WORKER_CONFIG"]}
                   python3 {app_path}
                """
    client = boto3.client('ec2', region_name=USER_REGION)
    response = client.run_instances(ImageId=WORKER_AMI_ID, InstanceType=INSTANCE_TYPE, MaxCount=max_count,
                                    MinCount=min_count, InstanceInitiatedShutdownBehavior='terminate',
                                    UserData=user_data, SecurityGroupIds=[const["SEC_GRP"]])
    return response


def check_time_first_in_line():
    dif = datetime.utcnow() - work_queue[0]["entry_time_utc"]
    return dif.seconds


@app.before_first_request
def scale_up():
    read_from_txt(PATH_TO_CONST_TXT)
    global next_call

    if work_queue and check_time_first_in_line() > MAX_Q_TIME_SEC:
        resource = boto3.resource('ec2', region_name=USER_REGION)
        response = deploy_worker(const["WORKER_APP"])
        instance = resource.Instance(id=response['Instances'][0]['InstanceId'])
        instance.wait_until_running()
    next_call = next_call + PERIODIC_ITERATION
    threading.Timer(next_call - time.time(), scale_up).start()


@app.route('/addJob', methods=['PUT'])
def add_job_to_queue():
    if request.method == "PUT":
        entry_time_utc = datetime.utcnow()
        work_queue.append({
            "job_id": uuid.uuid4().int,
            "entry_time_utc": entry_time_utc,
            "iterations": int(request.args.get("iterations")),
            "file": request.get_data()})
    return Response(status=200)


@app.route('/get_work', methods=['GET'])
def get_work():
    if request.method == "GET":
        if not work_queue:
            return Response(mimetype='application/json',
                            response=json.dumps({}),
                            status=200)
        else:
            job = work_queue[0]
            del work_queue[0]

            return Response(mimetype='application/json',
                            response=json.dumps({"job_id": job["job_id"],
                                                 "iterations": job["iterations"],
                                                 "file": str(job["file"]),
                                                 }),
                            status=200)


read_from_txt(PATH_TO_CONST_TXT)
deploy_worker(const["WORKER_APP"],
              exit_flag=False,
              min_count=1,
              max_count=1)
