from fastapi import FastAPI

from app.routers import example01, example02, example03, example04, login

app = FastAPI(title="Securing S3 Access — Demo Backend")

app.include_router(login.router)
app.include_router(example01.router)
app.include_router(example02.router)
app.include_router(example03.router)
app.include_router(example04.router)
