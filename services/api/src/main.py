from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException, Depends
#Base Model for Shape, HttpUrl for Type checking
from pydantic import BaseModel, HttpUrl, ConfigDict
from sqlalchemy.orm import Session

from src.database import Base, engine, get_db
from src.models import Monitor

app = FastAPI(title="Uptime Monitor API")

Base.metadata.create_all(bind=engine)

"""Base Models"""

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

# Base Model to send details to the DB
class MonitorOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    url: str
    check_interval_seconds: int
    notify_email: str | None
    status: str
    last_checked_at: str | None


""" API Section """
# Check to see if server is running
@app.get("/healthz")
def health_check():
    return {"status": "ok"}

# API to create a URL for monitoring
@app.post("/monitors", status_code=201, response_model=MonitorOut)
def create_monitor(monitor: MonitorCreate, db: Session = Depends(get_db)):
    new_monitor = Monitor(
        name=monitor.name,
        url=str(monitor.url),
        check_interval_seconds= monitor.check_interval_seconds,
        notify_email=monitor.notify_email,
    )
    db.add(new_monitor)
    db.commit()
    db.refresh(new_monitor)
    return new_monitor

# Show all Monitored URLs
@app.get("/monitors", response_model=list[MonitorOut])
def list_monitors(db: Session = Depends(get_db)):
    return db.query(Monitor).all()

#Provide Monitored URL ID and get all details
@app.get("/monitors/{monitor_id}", response_model=MonitorOut)
def get_monitor(monitor_id: int, db: Session = Depends(get_db)):
    monitor = db.query(Monitor).filter(Monitor.id == monitor_id).first()
    if monitor is None:
        raise HTTPException(status_code=404, detail="Monitored URL not found")
    return monitor

# Update operation on the monitored URLs
@app.patch("/monitors/{monitor_id}", response_model=MonitorOut)
def update_monitor(monitor_id: int, update: MonitorUpdate, db: Session= Depends(get_db)):
    monitor = db.query(Monitor).filter(Monitor.id == monitor_id).first()
    if monitor is None:
        raise HTTPException(status_code=404, detail="Monitored URL not found")
    changes = update.model_dump(exclude_unset=True)
    for key, value in changes.items():
        setattr(monitor, key, str(value) if key == "url" else value)

    db.commit()
    db.refresh(monitor)
    return monitor
        

# Delete a specific URL by providing monitor ID
@app.delete("/monitors/{monitor_id}", status_code = 204)
def delete_monitor(monitor_id: int, db: Session = Depends(get_db)):
    monitor = db.query(Monitor).filter(Monitor.id == monitor_id).first()
    if monitor is None:
        raise HTTPException(status_code=404, detail= "Monitored URL not found")
    db.delete(monitor)
    db.commit()