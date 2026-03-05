from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse

from app.auth import get_current_user
from app.s3 import bucket_for, get_s3_client

router = APIRouter()


@router.get("/api/01-backend-proxy/file/{file_id}")
def get_file(file_id: str, username: str = Depends(get_current_user)):
    """Backend acts as proxy: fetches the file from the user's own S3 bucket."""
    bucket = bucket_for(username)
    client = get_s3_client()

    try:
        response = client.get_object(Bucket=bucket, Key=file_id)
    except client.exceptions.NoSuchKey:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File not found")
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(e))

    content_type = response["ContentType"] if "ContentType" in response else "application/octet-stream"

    return StreamingResponse(response["Body"], media_type=content_type)
