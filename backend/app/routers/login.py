from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel

from app.auth import USERS, create_token

router = APIRouter()


class LoginRequest(BaseModel):
    username: str
    password: str


class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


@router.post("/api/login", response_model=LoginResponse)
def login(body: LoginRequest):
    expected = USERS.get(body.username)
    if expected is None or expected != body.password:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    token = create_token(body.username)
    return LoginResponse(access_token=token)
