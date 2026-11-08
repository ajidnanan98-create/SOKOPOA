import os
from typing import Generator
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker, Session

# Environment configurable PostgreSQL connection string or local fallback
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://sokopoa:sokopoa_secret@localhost:5432/sokopoa_db"
)

# Use SQLite fallback if PostgreSQL is not available in local dev environment
if DATABASE_URL.startswith("sqlite"):
    engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
else:
    try:
        engine = create_engine(DATABASE_URL, pool_pre_ping=True)
    except Exception:
        # Development fallback
        engine = create_engine("sqlite:///./sokopoa_server.db", connect_args={"check_same_thread": False})

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def get_db() -> Generator[Session, None, None]:
    """Dependency to provide a database session for FastAPI routes."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
