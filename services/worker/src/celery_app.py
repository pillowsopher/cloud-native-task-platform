import os

from celery import Celery

REDIS_URL = os.environ.get("REDIS_URL", "redis://redis:6379/0/")

app = Celery(
    "uptime_monitor",
    broker = REDIS_URL,
    backend = REDIS_URL,
    include=["src.tasks"],
)

app.conf.beat_schedule = {
    "dispatch-due-checks-every-15-seconds": {
        "task": "src.tasks.dispatch_due_checks",
        "schedule": 15.0
    },
}