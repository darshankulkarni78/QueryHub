from backend.db import Base, engine
from backend import models

def init():
    Base.metadata.create_all(bind=engine)
    print("DB tables created")

if __name__ == "__main__":
    init()
