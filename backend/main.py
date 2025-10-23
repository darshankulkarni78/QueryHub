import uvicorn
from fastapi import FastAPI
from .routes import app as routes_app

app = FastAPI(title="QueryHub Full App")
app.mount("/", routes_app)

if __name__ == "__main__":
    uvicorn.run("backend.main:app", host="0.0.0.0", port=8000, reload=True)