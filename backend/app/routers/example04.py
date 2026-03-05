from fastapi import APIRouter

router = APIRouter()


@router.get("/api/04-temp-credentials/access")
def temp_credentials_access():
    """Placeholder — example 04 is not yet implemented."""
    return {"detail": "not implemented"}
