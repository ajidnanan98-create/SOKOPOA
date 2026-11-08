from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Notification, AuditLog, SyncEvent
from app.security import get_current_user

router = APIRouter()


@router.get("/dashboard")
def get_remote_dashboard(
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Provides a consolidated real-time dashboard summary for remote administrators."""
    business_id = current_user.get("business_id", "default-business")

    unack_notifs = (
        db.query(Notification)
        .filter(Notification.business_id == business_id, Notification.acknowledged == False)
        .count()
    )

    recent_events = (
        db.query(SyncEvent)
        .filter(SyncEvent.business_id == business_id)
        .order_by(SyncEvent.received_at.desc())
        .limit(10)
        .all()
    )

    return {
        "unacknowledged_alerts_count": unack_notifs,
        "recent_synced_transactions": len(recent_events),
        "last_synced_at": recent_events[0].received_at.isoformat() if recent_events else None,
        "server_status": "active",
        "remote_access_enabled": True,
    }


@router.get("/notifications")
def get_remote_notifications(
    category: Optional[str] = None,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Returns remote notifications and business alerts."""
    business_id = current_user.get("business_id", "default-business")
    query = db.query(Notification).filter(Notification.business_id == business_id)

    if category:
        query = query.filter(Notification.category == category)

    notifs = query.order_by(Notification.created_at.desc()).limit(100).all()

    return [
        {
            "id": n.id,
            "title": n.title,
            "message": n.message,
            "category": n.category,
            "severity": n.severity,
            "acknowledged": n.acknowledged,
            "created_at": n.created_at.isoformat(),
        }
        for n in notifs
    ]


@router.post("/notifications/{notif_id}/acknowledge")
def acknowledge_notification(
    notif_id: str,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Marks a notification as acknowledged by the remote administrator."""
    business_id = current_user.get("business_id", "default-business")
    notif = (
        db.query(Notification)
        .filter(Notification.id == notif_id, Notification.business_id == business_id)
        .first()
    )

    if not notif:
        raise HTTPException(status_code=404, detail="Notification not found")

    notif.acknowledged = True
    db.commit()

    return {"success": True, "message": "Notification acknowledged"}
