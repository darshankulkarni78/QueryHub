import sys
from pathlib import Path
import uvicorn
from fastapi import FastAPI

# Allow running this file both as a package (python -m backend.main)
# and as a script (python main.py) when your CWD is the `backend/` folder.
if __package__ is None:
    # running as a script: add repository root to sys.path so `backend` package is importable
    repo_root = Path(__file__).resolve().parent.parent
    sys.path.insert(0, str(repo_root))
    from backend.routes import app as routes_app
else:
    # running as package/module, normal relative import works
    from .routes import app as routes_app

app = FastAPI(title="QueryHub Full App")
app.mount("/", routes_app)

if __name__ == "__main__":
    print("\nStarting QueryHub backend...")
    print("  > http://0.0.0.0:8000")
    print("  > GET /health - Health check")
    print("  > POST /upload - Upload a file")
    print("  > POST /ask - Ask a question\n")
    uvicorn.run(app, host="0.0.0.0", port=8000, reload=False)