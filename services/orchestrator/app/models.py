from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy import Column, String, Boolean, TIMESTAMP, Text, JSON
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from sqlalchemy import ForeignKey

Base = declarative_base()

class User(Base):
    __tablename__ = 'auth_users'
    id = Column(UUID(as_uuid=True), primary_key=True)
    username = Column(Text, unique=True, nullable=False)
    email = Column(Text, unique=True, nullable=False)
    hashed_password = Column(Text)
    is_active = Column(Boolean, default=True)
    created_at = Column(TIMESTAMP(timezone=True), server_default=func.now())
    updated_at = Column(TIMESTAMP(timezone=True), server_default=func.now())

class Role(Base):
    __tablename__ = 'roles'
    id = Column(UUID(as_uuid=True), primary_key=True)
    name = Column(Text, unique=True, nullable=False)
    description = Column(Text)

class UserRole(Base):
    __tablename__ = 'user_roles'
    user_id = Column(UUID(as_uuid=True), ForeignKey('auth_users.id', ondelete='CASCADE'), primary_key=True)
    role_id = Column(UUID(as_uuid=True), ForeignKey('roles.id', ondelete='CASCADE'), primary_key=True)

class Agent(Base):
    __tablename__ = 'agents'
    id = Column(UUID(as_uuid=True), primary_key=True)
    name = Column(Text, nullable=False)
    slug = Column(Text, nullable=False, unique=True)
    description = Column(Text)
    spec = Column(JSON, nullable=False)
    version = Column(Text, nullable=False)
    owner_id = Column(UUID(as_uuid=True), ForeignKey('auth_users.id'))
    created_at = Column(TIMESTAMP(timezone=True), server_default=func.now())
    updated_at = Column(TIMESTAMP(timezone=True), server_default=func.now())

class SubAgent(Base):
    __tablename__ = 'subagents'
    id = Column(UUID(as_uuid=True), primary_key=True)
    agent_id = Column(UUID(as_uuid=True), ForeignKey('agents.id', ondelete='CASCADE'))
    name = Column(Text)
    status = Column(Text, nullable=False)
    run_spec = Column(JSON)
    docker_container_id = Column(Text)
    created_at = Column(TIMESTAMP(timezone=True), server_default=func.now())
    started_at = Column(TIMESTAMP(timezone=True))
    finished_at = Column(TIMESTAMP(timezone=True))
    updated_at = Column(TIMESTAMP(timezone=True), server_default=func.now())

class Checkpoint(Base):
    __tablename__ = 'checkpoints'
    id = Column(UUID(as_uuid=True), primary_key=True)
    run_id = Column(UUID(as_uuid=True))
    state = Column(JSON)
    artifact_location = Column(Text)
    created_at = Column(TIMESTAMP(timezone=True), server_default=func.now())

class Run(Base):
    __tablename__ = 'runs'
    id = Column(UUID(as_uuid=True), primary_key=True)
    subagent_id = Column(UUID(as_uuid=True), ForeignKey('subagents.id', ondelete='CASCADE'))
    inputs = Column(JSON)
    outputs = Column(JSON)
    status = Column(Text, nullable=False)
    started_at = Column(TIMESTAMP(timezone=True))
    finished_at = Column(TIMESTAMP(timezone=True))
    checkpoint_id = Column(UUID(as_uuid=True))
    created_at = Column(TIMESTAMP(timezone=True), server_default=func.now())

class Approval(Base):
    __tablename__ = 'approvals'
    id = Column(UUID(as_uuid=True), primary_key=True)
    run_id = Column(UUID(as_uuid=True), ForeignKey('runs.id', ondelete='CASCADE'))
    requested_by = Column(UUID(as_uuid=True), ForeignKey('auth_users.id'))
    status = Column(Text, nullable=False)
    approver_id = Column(UUID(as_uuid=True), ForeignKey('auth_users.id'))
    reason = Column(Text)
    created_at = Column(TIMESTAMP(timezone=True), server_default=func.now())
    acted_at = Column(TIMESTAMP(timezone=True))

class AuditLog(Base):
    __tablename__ = 'audit_logs'
    id = Column(UUID(as_uuid=True), primary_key=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey('auth_users.id'))
    action = Column(Text)
    resource_type = Column(Text)
    resource_id = Column(UUID(as_uuid=True))
    details = Column(JSON)
    created_at = Column(TIMESTAMP(timezone=True), server_default=func.now())
