import os

# We set DB URL here, because, if we set it now, it will crash when we import src.main -> app 
os.environ["DATABASE_URL"] = "sqlite:///./test.db"

import pytest
from fastapi.testclient import TestClient

from src.database import Base, engine
from src.main import app

# We set autouse to True here, which wipes schema without each test explicitly asking for it
@pytest.fixture(autouse=True)
def reset_db():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    yield


@pytest.fixture
def client():
    return TestClient(app)
