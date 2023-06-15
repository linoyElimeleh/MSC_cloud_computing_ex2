#!/bin/bash
source "run/const.txt"
# Keys
KEY_NAME="CC-HW2-EC2-KEY"
SEC_GRP="CC_HW2_SEC_GRP"
KEY_PEM="$KEY_NAME.pem"
UBUNTU_AMI="ami-015c25ad8763b2f11"

GITHUB_URL="https://github.com/linoyElimeleh/cloud_computing_ex2"
PROJ_NAME="cloud_computing_ex2"

USER_REGION=$(aws configure get region --output text)
MY_IP=$(curl ipinfo.io/ip)
echo "PC_IP_ADDRESS: $MY_IP"

echo "creating ec2 key pair: $KEY_NAME"
aws ec2 create-key-pair --key-name "$KEY_NAME" \
| jq -r ".KeyMaterial" > "$KEY_PEM"

chmod 400 "$KEY_PEM"

echo "create security group $SEC_GRP"
aws ec2 create-security-group --group-name $SEC_GRP --description "Access my instances"

echo "allow ssh from $MY_IP only"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP --port 22 --protocol tcp \
    --cidr $MY_IP/32 | tr -d '"'

aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP --port 5000 --protocol tcp \
    --cidr $MY_IP/32 | tr -d '"'

function run_instance() {
  AMI_ID=$1
  printf "Creating Ubuntu 22.04 instance using %s...\n" "$AMI_ID"

  RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id "$AMI_ID"        \
    --instance-type t2.micro            \
    --key-name "$KEY_NAME"                \
    --security-groups "$SEC_GRP")

  INSTANCE_ID=$(echo "$RUN_INSTANCES" | jq -r '.Instances[0].InstanceId')

  printf "Waiting for instance creation...\n"
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

  PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids "$INSTANCE_ID" |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress')

  printf "New instance $INSTANCE_ID @ $PUBLIC_IP \n"

  echo $PUBLIC_IP $INSTANCE_ID

}

function setup_worker() {
  IMAGE_ID=$(aws ec2 describe-images --owners self --filters "Name=tag:$IMG_TAG_KEY_1,Values=[$IMG_TAG_VAL_1]" "Name=name, Values=[$AMI_NAME]" | jq --raw-output '.Images[] | .ImageId')

  if [[ $IMAGE_ID ]]
  then
    echo "$IMAGE_ID"
    return
  fi

  printf "AMO_ID:  %s...\n" "$AMI_ID"

  RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id $UBUNTU_AMI        \
    --instance-type t2.micro            \
    --key-name $KEY_NAME               \
    --security-groups "$SEC_GRP")

  INSTANCE_ID=$(echo "$RUN_INSTANCES" | jq -r '.Instances[0].InstanceId')
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

  PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids "$INSTANCE_ID" jq -r '.Reservations[0].Instances[0].PublicIpAddress')

  printf "New instance $INSTANCE_ID @ $PUBLIC_IP \n"

  printf "Deploy\n"
  ssh  -i "$KEY_PEM" -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=1600" ubuntu@"$PUBLIC_IP" <<EOF

      printf "update apt get\n"
      sudo apt-get update -y

      printf "upgrade apt get\n"
      sudo apt-get upgrade -y

      printf "update apt get x2\n"
      sudo apt-get update -y

      printf "install pip\n"
      sudo apt-get install python3-pip -y

      printf "Clone repo\n"
      git clone "$GITHUB_URL.git"
      cd $PROJ_NAME

      printf "Install requirements\n"
      pip3 install -r "worker/requirements.txt"
EOF

  printf "Creating new image...\n"
  IMAGE_ID=$(aws ec2 create-image --instance-id "$INSTANCE_ID" \
        --name "$AMI_NAME" \
        --tag-specifications ResourceType=image,Tags="[{Key=$IMG_TAG_KEY_1,Value=$IMG_TAG_VAL_1}]" \
        --description "Worker" \
        --region "$USER_REGION" \
        --query ImageId --output text)

  aws ec2 wait image-available --image-ids "$IMAGE_ID"

  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID"

  echo "$IMAGE_ID"
}

function deploy_orchestrator() {
  WORKER_AMI_ID=$1

  printf "Create IAM Role\n"
  aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$POLICY_PATH"

  echo "Attach a Policy with the Role\n"
  aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

  echo "Verify the policy assignment\n"
  aws iam create-instance-profile --instance-profile-name "$ROLE_NAME"

  echo "Creating Ubuntu instance using %s...\n" "$AMI_ID"

  RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id "$UBUNTU_AMI"        \
    --instance-type t2.micro            \
    --key-name "$KEY_NAME"                \
    --security-groups "$SEC_GRP")

  INSTANCE_ID=$(echo "$RUN_INSTANCES" | jq -r '.Instances[0].InstanceId')

  printf "Waiting for instance creation...\n"
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

  PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids "$INSTANCE_ID" |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress')

  printf "New instance $INSTANCE_ID @ $PUBLIC_IP \n"

  aws iam add-role-to-instance-profile --role-name "$ROLE_NAME" --instance-profile-name "$ROLE_NAME"

  printf "Associate IAM role to instance\n"
  aws ec2 associate-iam-instance-profile --instance-id "$INSTANCE_ID" --iam-instance-profile Name="$ROLE_NAME"

  printf "New end point - %s @ %s \n" "$INSTANCE_ID" "$PUBLIC_IP"

  printf "Deploy app\n"
  ssh -i "$KEY_PEM" -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@"$PUBLIC_IP" <<EOF

      printf "update apt get\n"
      sudo apt-get update -y

      printf "upgrade apt get\n"
      sudo apt-get upgrade -y

      printf "update apt get x2\n"
      sudo apt-get update -y

      printf "install pip\n"
      sudo apt-get install python3-pip -y

      printf "Clone repo\n"
      git clone "$GITHUB_URL.git"
      cd $PROJ_NAME

      echo WORKER_AMI_ID = "'$WORKER_AMI_ID'" >> "$LB_CONST"
      echo orchestrator_public_ip = "'$PUBLIC_IP'" >> "$LB_CONST"
      echo USER_REGION = "'$USER_REGION'" >> "$LB_CONST"

      printf "Install requirements\n"
      pip3 install -r "orchestrator/requirements.txt"

      export FLASK_APP="orchestrator/app.py"
      nohup flask run --host=0.0.0.0 &>/dev/null & exit
EOF

  echo "$PUBLIC_IP"

}

function deploy_api() {
  orchestrator_public_ip=$1

  printf "Creating Ubuntu 22.04 instance...\n"

  RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id "$UBUNTU_AMI"        \
    --instance-type t2.micro            \
    --key-name "$KEY_NAME"                \
    --security-groups "$SEC_GRP")

  INSTANCE_ID=$(echo "$RUN_INSTANCES" | jq -r '.Instances[0].InstanceId')

  printf "Waiting for instance creation...\n"
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

  PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids "$INSTANCE_ID" |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress')

  printf "New instance %s @ %s \n" "$INSTANCE_ID" "$PUBLIC_IP"

  printf "Deploy app"
  ssh -i "$KEY_PEM" -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@"$PUBLIC_IP" <<EOF

      echo "update apt get"
      sudo apt-get update -y

      echo "upgrade apt get"
      sudo apt-get upgrade -y

      echo "update apt get x2"
      sudo apt-get update -y

      echo "install pip"
      sudo apt-get install python3-pip -y

      echo "Clone repo"
      git clone "$GITHUB_URL.git"
      cd $PROJ_NAME

      echo "Install requirements"
      pip3 install -r "api/requirements.txt"

      echo orchestrator_public_ip = "'$orchestrator_public_ip'" >> "$END_POINT_CONST"

      export FLASK_APP="end_point/app.py"
      nohup flask run --host=0.0.0.0 &>/dev/null & exit
EOF

echo "$PUBLIC_IP"
}

AMI_NAME="worker"
IMG_TAG_KEY_1="service"
IMG_TAG_VAL_1="dynamic-workload"

ROLE_NAME="EC2FullAccess"
POLICY_PATH="file://run/trust-policy.json"

printf "Create worker AMI \n"
worker_AMI_logs=$(setup_worker)
echo "$worker_AMI_logs" >> worker_AMI_logs.txt
WORKER_AMI_ID=$(echo "$worker_AMI_logs" | tail -1)
printf "Using %s \n" "$WORKER_AMI_ID"

printf "Deploy orchestrator\n"
orchestrator_logs=$(deploy_orchestrator "$WORKER_AMI_ID")
echo "$orchestrator_logs" >> orchestrator_logs.txt
orchestrator_public_ip=$(echo "$orchestrator_logs" | tail -1)
printf "Orchestrator @ %s \n" "$orchestrator_public_ip"

printf "Deploy instance1 \n"
EP_1_logs=$(deploy_api "$orchestrator_public_ip")
echo "$EP_1_logs" >> EP_1_logs.txt
EP_1_PUBLIC_IP=$(echo "$EP_1_logs" | tail -1)
printf "New instance1 @ %s \n" "$EP_1_PUBLIC_IP"

printf "Deploy instance2"
EP_2_logs=$(deploy_api "$orchestrator_public_ip")
echo "$EP_2_logs" >> EP_2_logs.txt
EP_2_PUBLIC_IP=$(echo "$EP_2_logs" | tail -1)
printf "New instance2 @ %s \n" "$EP_2_PUBLIC_IP"