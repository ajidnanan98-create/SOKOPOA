from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.database import engine, Base
from app.routes import auth, sync, remote_admin

# Initialize database schema tables
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="SOKOPOA API",
    version="1.0.0",
    description="SOKOPOA Wholesale Management & Remote Administration API",
)

# Configure CORS for Flutter client communication
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/api/auth", tags=["authentication"])
app.include_router(sync.router, prefix="/api/sync", tags=["synchronization"])
app.include_router(remote_admin.router, prefix="/api/admin", tags=["remote-administration"])


@app.get("/health", tags=["system"])
def health():
    return {
        "status": "ok",
        "service": "sokopoa-api",
        "stage": "production-ready",
        "database": "connected",
    }


@app.get("/api/system/capabilities", tags=["system"])
def capabilities():
    return {
        "platforms": ["windows", "android"],
        "local_storage": "sqlite",
        "central_storage": "postgresql",
        "offline_first": True,
        "modules": {
            "products": "active",
            "sales": "active",
            "customers": "active",
            "suppliers": "active",
            "expenses": "active",
            "workers": "active",
            "sync": "active",
            "reports": "active",
            "notifications": "active",
            "audit": "active",
        },
    }
