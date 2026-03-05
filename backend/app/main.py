from fastapi import FastAPI

from app.routers import example04, login

app = FastAPI(title="Securing S3 Access — Demo Backend")

app.include_router(login.router)
app.include_router(example04.router)
