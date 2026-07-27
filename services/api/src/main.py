from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException
#Base Model for Shape, HttpUrl for Type checking
from pydantic import BaseModel, HttpUrl

app = FastAPI(title="Uptime Monitor API")

monitors: list[dict] = []

# Base Model Shape for res
class MonitorCreate(BaseModel):
    name: str
    url: HttpUrl
    check_interval_seconds: int = 60
    notify_email: str | None = None

# Base Model Shape for Updating URL info partially
class MonitorUpdate(BaseModel):
    name: str | None = None
    url: HttpUrl | None = None
    check_interval_seconds: int | None = None
    notify_email: str | None = None


# Check to see if server is running
@app.get("/healthz")
def health_check():
    return {"status": "ok"}

# API to create a URL for monitoring
@app.post("/monitors", status_code=201)
def create_monitor(monitor: MonitorCreate):
    new_monitor = {
        "id": len(monitors) + 1,
        "name": monitor.name,
        "url": str(monitor.url),
        "check_interval_seconds": monitor.check_interval_seconds,
        "notify_email": monitor.notify_email,
        "status": "unknown",
        "last_checked_at": None,
    }
    monitors.append(new_monitor)
    return new_monitor

# Show all Monitored URLs
@app.get("/monitors")
def list_monitors():
    return monitors

#Provide Monitored URL ID and get all details
@app.get("/monitors/{monitor_id}")
def get_monitor(monitor_id: int):
    for monitor in monitors:
        if monitor['id'] == monitor_id:
            return monitor
    raise HTTPException(status_code=404, detail="Monitored URL not found")

# Update operation on the monitored URLs
@app.patch("/monitors/{monitor_id}")
def update_monitor(monitor_id: int, update: MonitorUpdate):
    for monitor in monitors:
        if monitor["id"] == monitor_id:
            changes = update.model_dump(exclude_unset=True)
            for key, value in changes.items():
                monitor[key] = str(value) if key == "url" else value
            return monitor
    raise HTTPException(status_code=404, detail="Monitored URL not found")

# Delete a specific URL by providing monitor ID
@app.delete("/monitors/{monitor_id}", status_code = 204)
def delete_monitor(monitor_id: int):
    for i, monitor in enumerate(monitors):
        if monitor['id'] == monitor_id:
            monitors.pop(i)
            return
    raise HTTPException(status_code=404, detail= "Monitored URL not found")