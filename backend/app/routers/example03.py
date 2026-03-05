import os

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import RedirectResponse

from app.auth import get_current_user
from app.s3 import bucket_for, get_s3_client

router = APIRouter()

PRESIGNED_URL_TTL = int(os.getenv("PRESIGNED_URL_TTL_SECONDS", "30"))


@router.get("/api/03-presigned-uri/file/{file_id}")
def get_presigned_url(file_id: str, username: str = Depends(get_current_user)):
    """Generate a short-lived presigned URL for the user's file and redirect there."""
    bucket = bucket_for(username)
    client = get_s3_client()

    try:
        url = client.generate_presigned_url(
            "get_object",
            Params={"Bucket": bucket, "Key": file_id},
            ExpiresIn=PRESIGNED_URL_TTL,
        )
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(e))

    return RedirectResponse(url=url, status_code=302)
