from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import User, Business
from app.security import (
    hash_password,
    verify_password,
    create_access_token,
    get_current_user,
)

router = APIRouter()


class LoginRequest(BaseModel):
    username: str = Field(min_length=3, max_length=80)
    password: str = Field(min_length=6, max_length=256)


class BootstrapRequest(BaseModel):
    username: str = Field(min_length=3, max_length=80)
    password: str = Field(min_length=8, max_length=256)
    business_name: str = Field(default="SOKOPOA Wholesale")


class PasswordChangeRequest(BaseModel):
    old_password: str
    new_password: str = Field(min_length=8)


@router.post("/bootstrap")
def bootstrap_owner(body: BootstrapRequest, db: Session = Depends(get_db)):
    """Initializes the business owner account on first setup."""
    existing_owner = db.query(User).filter(User.role == "owner").first()
    if existing_owner:
        raise HTTPException(status_code=409, detail="Owner account already exists")

    business = Business(name=body.business_name)
    db.add(business)
    db.flush()

    owner = User(
        business_id=business.id,
        username=body.username.strip().lower(),
        password_hash=hash_password(body.password),
        role="owner",
        must_change_password=False,
    )
    db.add(owner)
    db.commit()

    return {
        "created": True,
        "username": owner.username,
        "business_id": business.id,
        "message": "Owner account bootstrapped successfully",
    }


@router.post("/login")
def login(body: LoginRequest, db: Session = Depends(get_db)):
    """Authenticates a user and returns a signed JWT access token."""
    username_clean = body.username.strip().lower()
    user = db.query(User).filter(User.username == username_clean).first()

    if not user or not verify_password(body.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid username or password",
        )

    if not user.active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is deactivated",
        )

    token = create_access_token(
        data={
            "sub": user.id,
            "username": user.username,
            "role": user.role,
            "business_id": user.business_id,
        }
    )

    return {
        "access_token": token,
        "token_type": "bearer",
        "username": user.username,
        "role": user.role,
        "must_change_password": user.must_change_password,
    }


@router.get("/me")
def get_me(current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Returns profile information for the authenticated user."""
    user = db.query(User).filter(User.id == current_user["sub"]).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return {
        "id": user.id,
        "username": user.username,
        "role": user.role,
        "business_id": user.business_id,
        "must_change_password": user.must_change_password,
    }


@router.post("/change-password")
def change_password(
    body: PasswordChangeRequest,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Allows an authenticated user to change their password."""
    user = db.query(User).filter(User.id == current_user["sub"]).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if not verify_password(body.old_password, user.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")

    user.password_hash = hash_password(body.new_password)
    user.must_change_password = False
    db.commit()

    return {"success": True, "message": "Password updated successfully"}
