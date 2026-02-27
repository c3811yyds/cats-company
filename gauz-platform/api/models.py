"""SQLAlchemy models for Gauz Platform."""

from datetime import datetime, timezone

from sqlalchemy import Column, Integer, String, Boolean, DateTime, Text, create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

from config import DATABASE_URL

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine)
Base = declarative_base()


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True)
    username = Column(String(64), unique=True, nullable=False, index=True)
    password_hash = Column(String(256), nullable=True, default="")
    display_name = Column(String(128), default="")
    invite_code = Column(String(64), default="")
    catscompany_uid = Column(Integer, default=0)
    catscompany_token = Column(String(512), default="")
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))


class Agent(Base):
    __tablename__ = "agents"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, nullable=False, index=True)
    name = Column(String(64), nullable=False)
    tenant_name = Column(String(32), unique=True, nullable=False)
    gauzmem_project_id = Column(String(64), default="")
    catscompany_uid = Column(Integer, default=0)
    status = Column(String(16), default="pending")  # pending/running/stopped
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))


class InviteCode(Base):
    __tablename__ = "invite_codes"

    id = Column(Integer, primary_key=True)
    code = Column(String(64), unique=True, nullable=False)
    max_uses = Column(Integer, default=1)
    used_count = Column(Integer, default=0)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))


class AgentMetrics(Base):
    """Per-agent conversation quality metrics, reported by agent containers."""
    __tablename__ = "agent_metrics"

    id = Column(Integer, primary_key=True)
    agent_id = Column(Integer, nullable=False, index=True)
    total_messages = Column(Integer, default=0)
    total_replies = Column(Integer, default=0)
    total_errors = Column(Integer, default=0)
    total_tokens_in = Column(Integer, default=0)
    total_tokens_out = Column(Integer, default=0)
    avg_latency_ms = Column(Integer, default=0)
    p95_latency_ms = Column(Integer, default=0)
    last_error = Column(String(512), default="")
    updated_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))


class AgentQuota(Base):
    """Per-agent resource quota and usage tracking."""
    __tablename__ = "agent_quotas"

    id = Column(Integer, primary_key=True)
    agent_id = Column(Integer, unique=True, nullable=False, index=True)
    daily_token_limit = Column(Integer, default=100000)
    monthly_token_limit = Column(Integer, default=2000000)
    daily_message_limit = Column(Integer, default=500)
    daily_tokens_used = Column(Integer, default=0)
    monthly_tokens_used = Column(Integer, default=0)
    daily_messages_used = Column(Integer, default=0)
    quota_reset_daily = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    quota_reset_monthly = Column(DateTime, default=lambda: datetime.now(timezone.utc))


def init_db():
    Base.metadata.create_all(engine)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
