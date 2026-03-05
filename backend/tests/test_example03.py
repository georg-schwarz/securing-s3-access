"""
Example 03 — Presigned URL.

The endpoint generates a short-lived presigned URL and redirects the client there.
S3 calls are mocked so no real S3 is required.
"""
from unittest.mock import MagicMock

import pytest

FAKE_URL = "http://localhost:3900/alice-bucket/report.txt?X-Amz-Expires=30&X-Amz-Signature=abc"


def test_redirects_to_presigned_url(client, alice_headers, mocker):
    s3 = MagicMock()
    s3.generate_presigned_url.return_value = FAKE_URL
    mocker.patch("app.routers.example03.get_s3_client", return_value=s3)

    r = client.get(
        "/api/03-presigned-uri/file/report.txt",
        headers=alice_headers,
        follow_redirects=False,
    )

    assert r.status_code == 302
    assert r.headers["location"] == FAKE_URL
    s3.generate_presigned_url.assert_called_once_with(
        "get_object",
        Params={"Bucket": "alice-bucket", "Key": "report.txt"},
        ExpiresIn=30,
    )


def test_bob_uses_bob_bucket(client, bob_headers, mocker):
    s3 = MagicMock()
    s3.generate_presigned_url.return_value = "http://s3/bob-bucket/data.csv?sig=x"
    mocker.patch("app.routers.example03.get_s3_client", return_value=s3)

    r = client.get(
        "/api/03-presigned-uri/file/data.csv",
        headers=bob_headers,
        follow_redirects=False,
    )

    assert r.status_code == 302
    s3.generate_presigned_url.assert_called_once_with(
        "get_object",
        Params={"Bucket": "bob-bucket", "Key": "data.csv"},
        ExpiresIn=30,
    )


def test_unauthenticated(client):
    r = client.get("/api/03-presigned-uri/file/report.txt", follow_redirects=False)
    assert r.status_code == 401


def test_s3_error_returns_502(client, alice_headers, mocker):
    s3 = MagicMock()
    s3.generate_presigned_url.side_effect = Exception("S3 unavailable")
    mocker.patch("app.routers.example03.get_s3_client", return_value=s3)

    r = client.get("/api/03-presigned-uri/file/report.txt", headers=alice_headers)
    assert r.status_code == 502


def test_custom_ttl(client, alice_headers, mocker, monkeypatch):
    monkeypatch.setenv("PRESIGNED_URL_TTL_SECONDS", "10")
    import importlib

    import app.routers.example03 as mod
    importlib.reload(mod)

    s3 = MagicMock()
    s3.generate_presigned_url.return_value = FAKE_URL
    mocker.patch("app.routers.example03.get_s3_client", return_value=s3)

    r = client.get(
        "/api/03-presigned-uri/file/report.txt",
        headers=alice_headers,
        follow_redirects=False,
    )
    assert r.status_code == 302
    s3.generate_presigned_url.assert_called_once_with(
        "get_object",
        Params={"Bucket": "alice-bucket", "Key": "report.txt"},
        ExpiresIn=10,
    )

    # restore default
    importlib.reload(mod)
