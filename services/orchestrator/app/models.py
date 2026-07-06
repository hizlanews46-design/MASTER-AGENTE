from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy import Column, String, Boolean, TIMESTAMP, Text, JSON
from sqlalchemy.dialects.postgresql import UUID

Base = declarative_base()

class User(Base):
    __tablename__ = 'auth_users'
    id = Column(UUID(as_uuid=True), primary_key=True)
    username = Column(Text, unique=True, nullable=False)
    email = Column(Text, unique=True, nullable=False)
    hashed_password = Column(Text)
    is_active = Column(Boolean, default=True)

# Other models can be added or imported by Alembic env
