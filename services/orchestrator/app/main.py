from fastapi import FastAPI
from .api import router as api_router
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST
from fastapi.responses import PlainTextResponse

app = FastAPI(title="Master Agent Orchestrator", version="1.0")
app.include_router(api_router, prefix="/api/v1")

@app.get("/health")
async def health():
    return {"status": "ok"}

@app.get("/metrics")
def metrics():
    resp = generate_latest()
    return PlainTextResponse(resp, media_type=CONTENT_TYPE_LATEST)
