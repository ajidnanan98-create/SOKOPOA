import uuid
from datetime import datetime
from sqlalchemy import (
    Column, String, Boolean, DateTime, Float, Integer, Text, JSON, ForeignKey
)
from sqlalchemy.orm import relationship
from app.database import Base


def generate_uuid() -> str:
    return str(uuid.uuid4())


class Business(Base):
    __tablename__ = "businesses"

    id = Column(String, primary_key=True, default=generate_uuid)
    name = Column(String, nullable=False)
    currency = Column(String, default="KES")
    created_at = Column(DateTime, default=datetime.utcnow)


class User(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True, default=generate_uuid)
    business_id = Column(String, ForeignKey("businesses.id"), nullable=False, default="default-business")
    username = Column(String, nullable=False, unique=True)
    password_hash = Column(String, nullable=False)
    role = Column(String, nullable=False, default="owner")  # owner, manager, cashier, worker
    full_name = Column(String, nullable=True)
    active = Column(Boolean, default=True)
    must_change_password = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)


class Device(Base):
    __tablename__ = "devices"

    id = Column(String, primary_key=True, default=generate_uuid)
    business_id = Column(String, ForeignKey("businesses.id"), nullable=False, default="default-business")
    device_name = Column(String, nullable=False)
    platform = Column(String, nullable=False)
    revoked = Column(Boolean, default=False)
    last_seen_at = Column(DateTime, default=datetime.utcnow)


class SyncEvent(Base):
    __tablename__ = "sync_events"

    event_id = Column(String, primary_key=True)
    business_id = Column(String, nullable=False, default="default-business")
    device_id = Column(String, nullable=False)
    aggregate_type = Column(String, nullable=False)
    aggregate_id = Column(String, nullable=False)
    event_type = Column(String, nullable=False)
    payload = Column(JSON, nullable=False)
    occurred_at = Column(DateTime, nullable=False)
    received_at = Column(DateTime, default=datetime.utcnow)


class Notification(Base):
    __tablename__ = "notifications"

    id = Column(String, primary_key=True, default=generate_uuid)
    business_id = Column(String, nullable=False, default="default-business")
    title = Column(String, nullable=False)
    message = Column(String, nullable=False)
    category = Column(String, nullable=False)  # stock, sale, sync, alert
    severity = Column(String, default="info")  # info, warning, danger
    acknowledged = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)


class AuditLog(Base):
    __tablename__ = "audit_log"

    id = Column(String, primary_key=True, default=generate_uuid)
    business_id = Column(String, nullable=False, default="default-business")
    actor_user_id = Column(String, nullable=True)
    device_id = Column(String, nullable=True)
    action = Column(String, nullable=False)
    entity_type = Column(String, nullable=False)
    entity_id = Column(String, nullable=True)
    previous_value = Column(JSON, nullable=True)
    new_value = Column(JSON, nullable=True)
    reason = Column(String, nullable=True)
    occurred_at = Column(DateTime, default=datetime.utcnow)
