"""initial migration

Revision ID: 0001_initial
Revises: 
Create Date: 2026-07-06 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '0001_initial'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";")
    op.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto;")

    op.create_table(
        'auth_users',
        sa.Column('id', sa.UUID(), primary_key=True, server_default=sa.text('uuid_generate_v4()')),
        sa.Column('username', sa.Text(), nullable=False, unique=True),
        sa.Column('email', sa.Text(), nullable=False, unique=True),
        sa.Column('hashed_password', sa.Text()),
        sa.Column('is_active', sa.Boolean(), server_default=sa.text('TRUE')),
        sa.Column('created_at', sa.TIMESTAMP(timezone=True), server_default=sa.text('now()')),
        sa.Column('updated_at', sa.TIMESTAMP(timezone=True), server_default=sa.text('now()')),
    )

    op.create_table(
        'roles',
        sa.Column('id', sa.UUID(), primary_key=True, server_default=sa.text('uuid_generate_v4()')),
        sa.Column('name', sa.Text(), nullable=False, unique=True),
        sa.Column('description', sa.Text()),
    )

    op.create_table(
        'user_roles',
        sa.Column('user_id', sa.UUID(), sa.ForeignKey('auth_users.id', ondelete='CASCADE')),
        sa.Column('role_id', sa.UUID(), sa.ForeignKey('roles.id', ondelete='CASCADE')),
        sa.PrimaryKeyConstraint('user_id', 'role_id')
    )

    op.create_table(
        'agents',
        sa.Column('id', sa.UUID(), primary_key=True, server_default=sa.text('uuid_generate_v4()')),
        sa.Column('name', sa.Text(), nullable=False),
        sa.Column('slug', sa.Text(), nullable=False, unique=True),
        sa.Column('description', sa.Text()),
        sa.Column('spec', sa.JSON(), nullable=False),
        sa.Column('version', sa.Text(), nullable=False, server_default='v1'),
        sa.Column('owner_id', sa.UUID(), sa.ForeignKey('auth_users.id')),
        sa.Column('created_at', sa.TIMESTAMP(timezone=True), server_default=sa.text('now()')),
        sa.Column('updated_at', sa.TIMESTAMP(timezone=True), server_default=sa.text('now()')),
    )

    op.create_table(
        'subagents',
        sa.Column('id', sa.UUID(), primary_key=True, server_default=sa.text('uuid_generate_v4()')),
        sa.Column('agent_id', sa.UUID(), sa.ForeignKey('agents.id', ondelete='CASCADE')),
        sa.Column('name', sa.Text()),
        sa.Column('status', sa.Text(), nullable=False),
        sa.Column('run_spec', sa.JSON()),
        sa.Column('docker_container_id', sa.Text()),
        sa.Column('created_at', sa.TIMESTAMP(timezone=True), server_default=sa.text('now()')),
        sa.Column('started_at', sa.TIMESTAMP(timezone=True)),
        sa.Column('finished_at', sa.TIMESTAMP(timezone=True)),
        sa.Column('updated_at', sa.TIMESTAMP(timezone=True), server_default=sa.text('now()')),
    )

    op.create_table(
        'prompts',
        sa.Column('id', sa.UUID(), primary_key=True, server_default=sa.text('uuid_generate_v4()')),
        sa.Column('name', sa.Text(), nullable=False),
        sa.Column('content', sa.Text(), nullable=False),
        sa.Column('metadata', sa.JSON()),
        sa.Column('created_by', sa.UUID(), sa.ForeignKey('auth_users.id')),
        sa.Column('created_at', sa.TIMESTAMP(timezone=True), server_default=sa.text('now()')),
    )

    op.create_table(
        'checkpoints',
        sa.Column('id', sa.UUID(), primary_key=True, server_default=sa.text('uuid_generate_v4()')),
        sa.Column('run_id', sa.UUID(), sa.ForeignKey('runs.id', ondelete='SET NULL')),
        sa.Column('state', sa.JSON()),
        sa.Column('artifact_location', sa.Text()),
        sa.Column('created_at', sa.TIMESTAMP(timezone=True), server_default=sa.text('now()')),
    )

    # runs depends on checkpoints so create after
    op.create_table(
        'runs',
        sa.Column('id', sa.UUID(), primary_key=True, server_default=sa.text('uuid_generate_v4()')),
        sa.Column('subagent_id', sa.UUID(), sa.ForeignKey('subagents.id', ondelete='CASCADE')),
        sa.Column('inputs', sa.JSON()),
        sa.Column('outputs', sa.JSON()),
        sa.Column('status', sa.Text(), nullable=False),
        sa.Column('started_at', sa.TIMESTAMP(timezone=True)),
        sa.Column('finished_at', sa.TIMESTAMP(timezone=True)),
        sa.Column('checkpoint_id', sa.UUID(), sa.ForeignKey('checkpoints.id')),
        sa.Column('created_at', sa.TIMESTAMP(timezone=True), server_default=sa.text('now()')),
    )

    op.create_table(
        'approvals',
        sa.Column('id', sa.UUID(), primary_key=True, server_default=sa.text('uuid_generate_v4()')),
        sa.Column('run_id', sa.UUID(), sa.ForeignKey('runs.id', ondelete='CASCADE')),
        sa.Column('requested_by', sa.UUID(), sa.ForeignKey('auth_users.id')),
        sa.Column('status', sa.Text(), nullable=False),
        sa.Column('approver_id', sa.UUID(), sa.ForeignKey('auth_users.id')),
        sa.Column('reason', sa.Text()),
        sa.Column('created_at', sa.TIMESTAMP(timezone=True), server_default=sa.text('now()')),
        sa.Column('acted_at', sa.TIMESTAMP(timezone=True)),
    )

    op.create_table(
        'audit_logs',
        sa.Column('id', sa.UUID(), primary_key=True, server_default=sa.text('uuid_generate_v4()')),
        sa.Column('user_id', sa.UUID(), sa.ForeignKey('auth_users.id')),
        sa.Column('action', sa.Text()),
        sa.Column('resource_type', sa.Text()),
        sa.Column('resource_id', sa.UUID()),
        sa.Column('details', sa.JSON()),
        sa.Column('created_at', sa.TIMESTAMP(timezone=True), server_default=sa.text('now()')),
    )

    op.create_index('idx_agents_slug', 'agents', ['slug'])
    op.create_index('idx_runs_status', 'runs', ['status'])


def downgrade():
    op.drop_index('idx_runs_status', table_name='runs')
    op.drop_index('idx_agents_slug', table_name='agents')
    op.drop_table('audit_logs')
    op.drop_table('approvals')
    op.drop_table('runs')
    op.drop_table('checkpoints')
    op.drop_table('prompts')
    op.drop_table('subagents')
    op.drop_table('agents')
    op.drop_table('user_roles')
    op.drop_table('roles')
    op.drop_table('auth_users')
