import os

from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

#Read connection string
DATABASE_URL = os.environ.get("DATABASE_URL")
if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL environment variable is not set")


engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
#Parent class that converts plain Python class to SQLAlchemy can track
Base = declarative_base()

# get_db() is a fastAPI dependency, hands a route, a database session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()