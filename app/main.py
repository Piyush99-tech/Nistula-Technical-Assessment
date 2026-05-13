from fastapi import FastAPI

from app.config.settings import settings
from app.routes.webhook import router as webhook_router


app = FastAPI(title=settings.app_name)

app.include_router(webhook_router)


@app.get("/")
async def health_check() -> dict:
    return {"status": "ok", "app": settings.app_name}
