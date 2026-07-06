from pydantic import BaseModel, Field
from typing import Optional, Dict, Any, List
from uuid import UUID

class AgentSpec(BaseModel):
    name: str
    version: Optional[str] = 'v1'
    description: Optional[str]
    capabilities: Optional[List[str]] = []
    runtime: Optional[Dict[str, Any]]
    prompts: Optional[Dict[str, str]]

class AgentCreate(BaseModel):
    name: str
    slug: str
    description: Optional[str]
    spec: AgentSpec

class AgentOut(BaseModel):
    id: UUID
    name: str
    slug: str
    description: Optional[str]
    spec: Dict[str, Any]

class SpawnInput(BaseModel):
    input: Optional[Dict[str, Any]] = {}

class RunOut(BaseModel):
    id: UUID
    subagent_id: UUID
    status: str
    inputs: Optional[Dict[str, Any]]
    outputs: Optional[Dict[str, Any]]

class ApprovalAct(BaseModel):
    action: str = Field(..., regex='^(approve|reject)$')
    reason: Optional[str]
