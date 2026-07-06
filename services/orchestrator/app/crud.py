from typing import Optional, Dict, Any
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from app.models import Agent, SubAgent, Run, Approval
from app.db import AsyncSessionLocal
from uuid import uuid4
from app.metrics import RUNS_CREATED

async def create_agent_async(payload: Dict[str, Any], owner_id: Optional[str] = None):
    async with AsyncSessionLocal() as session:
        agent = Agent(id=str(uuid4()), name=payload.get('name'), slug=payload.get('slug'), description=payload.get('description'), spec=payload.get('spec'), version=payload.get('spec', {}).get('version', 'v1'), owner_id=owner_id)
        session.add(agent)
        await session.commit()
        await session.refresh(agent)
        return agent

async def list_agents_async():
    async with AsyncSessionLocal() as session:
        res = await session.execute(select(Agent))
        return res.scalars().all()

async def get_agent_async(agent_id: str):
    async with AsyncSessionLocal() as session:
        res = await session.execute(select(Agent).where(Agent.id == agent_id))
        return res.scalar_one_or_none()

async def create_subagent_and_run(agent_id: str, run_input: Dict[str, Any], owner_id: Optional[str] = None):
    async with AsyncSessionLocal() as session:
        sub = SubAgent(id=str(uuid4()), agent_id=agent_id, name=f"{agent_id}-run", status='queued', run_spec=run_input)
        session.add(sub)
        await session.flush()
        run = Run(id=str(uuid4()), subagent_id=sub.id, inputs=run_input, status='queued')
        session.add(run)
        await session.commit()
        await session.refresh(run)
        # metrics
        try:
            RUNS_CREATED.inc()
        except Exception:
            pass
        return sub, run

async def update_run_status(run_id: str, status: str, outputs: Optional[Dict[str, Any]] = None):
    async with AsyncSessionLocal() as session:
        await session.execute(update(Run).where(Run.id == run_id).values(status=status))
        await session.commit()

async def create_approval_for_run(run_id: str, requested_by: Optional[str] = None, reason: Optional[str] = None):
    async with AsyncSessionLocal() as session:
        approval = Approval(id=str(uuid4()), run_id=run_id, requested_by=requested_by, status='requested', reason=reason)
        session.add(approval)
        await session.commit()
        await session.refresh(approval)
        return approval

async def act_on_approval(approval_id: str, action: str, approver_id: Optional[str] = None, reason: Optional[str] = None):
    async with AsyncSessionLocal() as session:
        appv = await session.get(Approval, approval_id)
        if not appv:
            return None
        appv.status = 'approved' if action == 'approve' else 'rejected'
        appv.approver_id = approver_id
        appv.reason = reason
        await session.commit()
        await session.refresh(appv)
        return appv

async def get_approval(approval_id: str):
    async with AsyncSessionLocal() as session:
        return await session.get(Approval, approval_id)

async def get_run(run_id: str):
    async with AsyncSessionLocal() as session:
        return await session.get(Run, run_id)
