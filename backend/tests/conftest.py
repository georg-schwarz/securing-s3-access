import io
import os

import pytest
from fastapi.testclient import TestClient

# Set required env vars before the app module is imported
os.environ.setdefault("JWT_SECRET", "test-secret")
os.environ.setdefault("S3_ENDPOINT_URL", "http://localhost:3900")
os.environ.setdefault("S3_ACCESS_KEY_ID", "test-key")
os.environ.setdefault("S3_SECRET_ACCESS_KEY", "test-secret-key")

from app.auth import create_token  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture
def client():
    with TestClient(app, raise_server_exceptions=True) as c:
        yield c


@pytest.fixture
def alice_token():
    return create_token("alice")


@pytest.fixture
def bob_token():
    return create_token("bob")


@pytest.fixture
def alice_headers(alice_token):
    return {"Authorization": f"Bearer {alice_token}"}


@pytest.fixture
def bob_headers(bob_token):
    return {"Authorization": f"Bearer {bob_token}"}


def make_s3_get_object_response(body: bytes = b"hello", content_type: str = "text/plain"):
    """Return a minimal boto3 get_object response dict."""
    return {
        "Body": io.BytesIO(body),
        "ContentType": content_type,
        "ContentLength": len(body),
        "ResponseMetadata": {},
    }
