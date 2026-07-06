from fastapi import APIRouter
from . import __init__ as routes

router = APIRouter()
router.include_router(routes.router)
