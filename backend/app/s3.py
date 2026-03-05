import os

import boto3


def _require(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"Required environment variable '{name}' is not set")
    return value


S3_ENDPOINT = _require("S3_ENDPOINT_URL")
S3_ACCESS_KEY = _require("S3_ACCESS_KEY_ID")
S3_SECRET_KEY = _require("S3_SECRET_ACCESS_KEY")
S3_REGION = os.getenv("S3_REGION", "garage")


def bucket_for(username: str) -> str:
    return f"{username}-bucket"


def get_s3_client():
    return boto3.client(
        "s3",
        endpoint_url=S3_ENDPOINT,
        aws_access_key_id=S3_ACCESS_KEY,
        aws_secret_access_key=S3_SECRET_KEY,
        region_name=S3_REGION,
    )
