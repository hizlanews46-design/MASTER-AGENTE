from fastapi import FastAPI
from fastapi.responses import PlainTextResponse
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST

app = FastAPI(title="Master Agent Orchestrator", version="1.0")

@app.get("/health")
async def health():
    return {"status": "ok"}

@app.get("/metrics")
def metrics():
    resp = generate_latest()
    return PlainTextResponse(resp, media_type=CONTENT_TYPE_LATEST)

# API routers and services to be implemented in app/api
