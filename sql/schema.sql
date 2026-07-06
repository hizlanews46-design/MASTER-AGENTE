-- Core schema for Master Agent Platform (PostgreSQL)
-- Extensions recommended: pgcrypto, citext
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- users and roles (RBAC)
CREATE TABLE auth_users (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  username TEXT UNIQUE NOT NULL,
  email TEXT UNIQUE NOT NULL,
  hashed_password TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE roles (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT UNIQUE NOT NULL,
  description TEXT
);

CREATE TABLE user_roles (
  user_id uuid REFERENCES auth_users(id) ON DELETE CASCADE,
  role_id uuid REFERENCES roles(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, role_id)
);

-- agent manifests (templates)
CREATE TABLE agents (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  description TEXT,
  spec JSONB NOT NULL,
  version TEXT NOT NULL DEFAULT 'v1',
  owner_id uuid REFERENCES auth_users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- subagents (deployed instances)
CREATE TABLE subagents (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  agent_id uuid REFERENCES agents(id) ON DELETE CASCADE,
  name TEXT,
  status TEXT NOT NULL,
  run_spec JSONB,
  docker_container_id TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  started_at TIMESTAMP WITH TIME ZONE,
  finished_at TIMESTAMP WITH TIME ZONE,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- prompts and prompt bundles
CREATE TABLE prompts (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  content TEXT NOT NULL,
  metadata JSONB,
  created_by uuid REFERENCES auth_users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- runs (executions)
CREATE TABLE runs (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  subagent_id uuid REFERENCES subagents(id) ON DELETE CASCADE,
  inputs JSONB,
  outputs JSONB,
  status TEXT NOT NULL,
  started_at TIMESTAMP WITH TIME ZONE,
  finished_at TIMESTAMP WITH TIME ZONE,
  checkpoint_id uuid REFERENCES checkpoints(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- checkpoints (for recovery)
CREATE TABLE checkpoints (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  run_id uuid REFERENCES runs(id) ON DELETE SET NULL,
  state JSONB,
  artifact_location TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- approvals (human approval layer)
CREATE TABLE approvals (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  run_id uuid REFERENCES runs(id) ON DELETE CASCADE,
  requested_by uuid REFERENCES auth_users(id),
  status TEXT NOT NULL,
  approver_id uuid REFERENCES auth_users(id),
  reason TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  acted_at TIMESTAMP WITH TIME ZONE
);

-- audit logs
CREATE TABLE audit_logs (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid REFERENCES auth_users(id),
  action TEXT,
  resource_type TEXT,
  resource_id uuid,
  details JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- index and performance
CREATE INDEX idx_agents_slug ON agents(slug);
CREATE INDEX idx_runs_status ON runs(status);
