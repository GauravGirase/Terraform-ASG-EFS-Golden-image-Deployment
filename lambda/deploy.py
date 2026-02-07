import os
import subprocess
import boto3

EFS_PATH = "/mnt/efs"
ASG_NAME = "web-asg"   # update if needed

asg = boto3.client("autoscaling")

def lambda_handler(event, context):
    version = event.get("version", "v1")

    release_path = f"{EFS_PATH}/releases/{version}"
    current_path = f"{EFS_PATH}/current"

    if not os.path.exists(release_path):
        raise Exception(f"Release {version} not found")

    subprocess.run(["sudo", "ln", "-sfn", release_path, current_path], check=True)

    # Optional: refresh ASG
    asg.start_instance_refresh(
        AutoScalingGroupName=ASG_NAME,
        Strategy="Rolling"
    )

    return {
        "status": "success",
        "active_version": version
    }
