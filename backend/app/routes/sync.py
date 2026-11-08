from datetime import datetime
from typing import Any, List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import SyncEvent, AuditLog, Notification
from app.security import get_current_user

router = APIRouter()


class SyncOutboxItem(BaseModel):
    event_id: str
    aggregate_type: str
    aggregate_id: str
    event_type: str
    payload: Any
    occurred_at: str


class SyncPushRequest(BaseModel):
    device_id: str
    events: List[SyncOutboxItem]


@router.post("/push")
def sync_push(
    body: SyncPushRequest,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Processes queued offline outbox items sent from client devices idempotently."""
    processed_ids = []
    duplicate_ids = []

    business_id = current_user.get("business_id", "default-business")
    user_id = current_user.get("sub", "anonymous")

    for item in body.events:
        existing = db.query(SyncEvent).filter(SyncEvent.event_id == item.event_id).first()
        if existing:
            duplicate_ids.append(item.event_id)
            continue

        try:
            occurred_dt = datetime.fromisoformat(item.occurred_at.replace("Z", "+00:00"))
        except Exception:
            occurred_dt = datetime.utcnow()

        event = SyncEvent(
            event_id=item.event_id,
            business_id=business_id,
            device_id=body.device_id,
            aggregate_type=item.aggregate_type,
            aggregate_id=item.aggregate_id,
            event_type=item.event_type,
            payload=item.payload if isinstance(item.payload, dict) else {"data": item.payload},
            occurred_at=occurred_dt,
        )
        db.add(event)

        # Record corresponding audit log for sync tracking
        audit = AuditLog(
            business_id=business_id,
            actor_user_id=user_id,
            device_id=body.device_id,
            action=f"sync:{item.event_type}",
            entity_type=item.aggregate_type,
            entity_id=item.aggregate_id,
            new_value=item.payload if isinstance(item.payload, dict) else {"data": item.payload},
            occurred_at=occurred_dt,
        )
        db.add(audit)

        # Automatically create notification if appropriate
        if item.aggregate_type == "sale":
            notif = Notification(
                business_id=business_id,
                title="New Remote Sale Synchronized",
                message=f"Sale transaction {item.aggregate_id} synchronized from device {body.device_id}.",
                category="sale",
                severity="info",
            )
            db.add(notif)
        elif item.aggregate_type == "stock_movement" and item.event_type in ("damaged", "expired", "lost"):
            notif = Notification(
                business_id=business_id,
                title="Stock Exception Logged",
                message=f"Stock movement ({item.event_type}) recorded for item {item.aggregate_id}.",
                category="stock",
                severity="warning",
            )
            db.add(notif)

        processed_ids.append(item.event_id)

    db.commit()

    return {
        "status": "success",
        "processed_count": len(processed_ids),
        "processed_ids": processed_ids,
        "duplicate_ids": duplicate_ids,
        "server_timestamp": datetime.utcnow().isoformat(),
    }


@router.get("/pull")
def sync_pull(
    since_timestamp: Optional[str] = None,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Returns server-side events and remote updates recorded since given timestamp."""
    business_id = current_user.get("business_id", "default-business")
    query = db.query(SyncEvent).filter(SyncEvent.business_id == business_id)

    if since_timestamp:
        try:
            dt = datetime.fromisoformat(since_timestamp.replace("Z", "+00:00"))
            query = query.filter(SyncEvent.received_at > dt)
        except Exception:
            pass

    events = query.order_by(SyncEvent.received_at.asc()).limit(200).all()

    return {
        "events": [
            {
                "event_id": e.event_id,
                "aggregate_type": e.aggregate_type,
                "aggregate_id": e.aggregate_id,
                "event_type": e.event_type,
                "payload": e.payload,
                "occurred_at": e.occurred_at.isoformat(),
                "received_at": e.received_at.isoformat(),
            }
            for e in events
        ],
        "server_timestamp": datetime.utcnow().isoformat(),
    }


@router.get("/status")
def sync_status(
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Returns server synchronization status, active device metrics, and system time."""
    business_id = current_user.get("business_id", "default-business")
    total_events = db.query(SyncEvent).filter(SyncEvent.business_id == business_id).count()

    return {
        "online": True,
        "server_time": datetime.utcnow().isoformat(),
        "total_synced_events": total_events,
        "message": "SOKOPOA Central Synchronization Server Active",
    }
