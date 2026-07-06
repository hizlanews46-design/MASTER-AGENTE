from fastapi import APIRouter, HTTPException, BackgroundTasks
from typing import List
from app.schemas import AgentCreate, AgentOut, SpawnInput, RunOut, ApprovalAct
from app import crud
from uuid import UUID
import os
from rq import Queue
from redis import Redis

router = APIRouter()

REDIS_URL = os.environ.get('REDIS_URL', 'redis://redis:6379/0')
redis_conn = Redis.from_url(REDIS_URL)
queue = Queue('default', connection=redis_conn)

@router.post('/agents', response_model=AgentOut, status_code=201)
async def create_agent(payload: AgentCreate):
    agent = await crud.create_agent_async(payload.dict())
    return {
        'id': agent.id,
        'name': agent.name,
        'slug': agent.slug,
        'description': agent.description,
        'spec': agent.spec
    }

@router.get('/agents', response_model=List[AgentOut])
async def list_agents():
    agents = await crud.list_agents_async()
    return [{'id': a.id, 'name': a.name, 'slug': a.slug, 'description': a.description, 'spec': a.spec} for a in agents]

@router.get('/agents/{agent_id}', response_model=AgentOut)
async def get_agent(agent_id: UUID):
    agent = await crud.get_agent_async(str(agent_id))
    if not agent:
        raise HTTPException(status_code=404, detail='Agent not found')
    return {'id': agent.id, 'name': agent.name, 'slug': agent.slug, 'description': agent.description, 'spec': agent.spec}

@router.post('/agents/{agent_id}/spawn', status_code=202)
async def spawn_agent(agent_id: UUID, payload: SpawnInput):
    # create subagent and run stub in DB
    sub, run = await crud.create_subagent_and_run(str(agent_id), payload.input or {})
    # enqueue worker job
    job = queue.enqueue('app.tasks.execute_run', run.id)
    return {'run_id': run.id, 'job_id': job.get_id(), 'status': 'queued'}

@router.get('/runs/{run_id}', response_model=RunOut)
async def get_run(run_id: UUID):
    r = await crud.get_run(str(run_id))
    if not r:
        raise HTTPException(status_code=404, detail='Run not found')
    return {'id': r.id, 'subagent_id': r.subagent_id, 'status': r.status, 'inputs': r.inputs, 'outputs': r.outputs}

@router.post('/runs/{run_id}/request-approval', status_code=201)
async def request_approval(run_id: UUID, payload: dict):
    approval = await crud.create_approval_for_run(str(run_id), requested_by=None, reason=payload.get('reason'))
    return {'approval_id': approval.id, 'status': approval.status}

@router.post('/approvals/{approval_id}/act')
async def act_approval(approval_id: UUID, payload: ApprovalAct):
    appv = await crud.act_on_approval(str(approval_id), payload.action, approver_id=None, reason=payload.reason)
    if not appv:
        raise HTTPException(status_code=404, detail='Approval not found')
    return {'id': appv.id, 'status': appv.status}
