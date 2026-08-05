from sqlalchemy import Column, DateTime, Integer, String
from src.database import Base


class Monitor(Base):
    __tablename__ = "monitors"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    url = Column(String, nullable=False)
    check_interval_seconds = Column(Integer, default=60)
    notify_email = Column(String, nullable=True)
    status = Column(String, default="unknown")
    #Changed this to help standardize models for Celery
    last_checked_at = Column(DateTime(timezone=True), nullable=True)
