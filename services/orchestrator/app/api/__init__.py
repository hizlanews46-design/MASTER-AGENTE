from fastapi import APIRouter

router = APIRouter()

@router.get('/agents')
async def list_agents():
    return {"agents": []}

@router.post('/agents')
async def create_agent(payload: dict):
    return {"id": "todo", "payload": payload}
