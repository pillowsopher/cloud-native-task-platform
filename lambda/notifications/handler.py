import json
import time
import uuid

import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table("uptime-monitor-notifications")

def handler(event, context):
    for record in event["Records"]:
        body = json.loads(record["body"])
        table.put_item(
            Item={
                "id": str(uuid.uuid4()),
                "monitor_id": body.get("monitor_id"),
                "monitor_name": body.get("monitor_name"),
                "status": body.get("status"),
                "timestamp": int(time.time())
            }
        )
        print(f"Logged notification for monitor {body.get('monitor_name')}: {body.get('status')}")
    return {"statusCode": 200}