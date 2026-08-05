""" This module defines tasks that would be performed by Celery"""
import json
import logging
import os
from datetime import datetime, timedelta, timezone

import boto3
import requests
from src.celery_app import app
from src.database import SessionLocal
from src.models import Monitor

logger = logging.getLogger(__name__)

# This task primarily checks when there was a health check, if it was not performed within our check_interval, it performs the check
@app.task(name="src.tasks.dispatch_due_checks")
def dispatch_due_checks():
    db = SessionLocal()
    try:
        now = datetime.now(timezone.utc)
        for monitor in db.query(Monitor).all():
            due = (
                monitor.last_checked_at is None
                or now - monitor.last_checked_at >= timedelta(seconds=monitor.check_interval_seconds)
            )
            # This delay does not immediately get triggered, 
            # rather it would queue in broker and start as new independent job
            if due:
                check_monitor.delay(monitor.id)
    finally:
        db.close()


# This task actually sends a request and checks whether the URL is 'UP' or 'DOWN'
# It updates the DB with the status, if there is a notification to be sent,
# It will queue it up in broker (Redis) [delay command] and create a new independent job
@app.task(name="src.tasks.check_monitor")
def check_monitor(monitor_id: int):
    db = SessionLocal()
    try:
        monitor = db.query(Monitor).filter(Monitor.id == monitor_id).first()
        if monitor is None:
            return

        previous_status = monitor.status
        try:
            response = requests.get(monitor.url, timeout = 10)
            new_status = "up" if response.status_code < 400 else "down"
        except requests.RequestException:
            new_status = "down"

        monitor.status = new_status
        monitor.last_checked_at = datetime.now(timezone.utc)
        db.commit()

        if previous_status != new_status and new_status == "down" and monitor.notify_email:
            send_notification.delay(monitor.id)
    finally:
        db.close()


# This task is used to trigger SQS notifications, which in turn call Lambda functions, and send data to DynamoDB
@app.task(name="src.tasks.send_notification")
def send_notification(monitor_id: int):
    db = SessionLocal()
    try:
        monitor = db.query(Monitor).filter(monitor_id == Monitor.id).first()
        if monitor is None:
            return
        logger.info("Would email %s: monitor '%s' (%s) is DOWN!",
                    monitor.notify_email, monitor.name, monitor.url)

        sqs = boto3.client("sqs")
        queue_url = sqs.get_queue_url(QueueName=os.environ["SQS_QUEUE_NAME"])["QueueUrl"]
        sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps({
                "monitor_id": monitor.id,
                "monitor_name": monitor.name,
                "status": monitor.status,
            }),
        )
    finally:
        db.close()
