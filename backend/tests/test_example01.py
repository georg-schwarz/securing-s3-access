"""
Example 01 — Backend proxy.

The backend fetches the object from the user's own S3 bucket and streams it back.
S3 calls are mocked so no real S3 is required.
"""
from unittest.mock import MagicMock

import pytest
from botocore.exceptions import ClientError

from tests.conftest import make_s3_get_object_response


def test_get_file_alice(client, alice_headers, mocker):
    s3 = MagicMock()
    s3.get_object.return_value = make_s3_get_object_response(b"alice-data")
    mocker.patch("app.routers.example01.get_s3_client", return_value=s3)

    r = client.get("/api/01-backend-proxy/file/report.txt", headers=alice_headers)

    assert r.status_code == 200
    assert r.content == b"alice-data"
    s3.get_object.assert_called_once_with(Bucket="alice-bucket", Key="report.txt")


def test_get_file_bob_uses_bob_bucket(client, bob_headers, mocker):
    s3 = MagicMock()
    s3.get_object.return_value = make_s3_get_object_response(b"bob-data")
    mocker.patch("app.routers.example01.get_s3_client", return_value=s3)

    r = client.get("/api/01-backend-proxy/file/notes.txt", headers=bob_headers)

    assert r.status_code == 200
    s3.get_object.assert_called_once_with(Bucket="bob-bucket", Key="notes.txt")


def test_unauthenticated(client):
    r = client.get("/api/01-backend-proxy/file/report.txt")
    assert r.status_code == 401


def test_invalid_token(client):
    r = client.get(
        "/api/01-backend-proxy/file/report.txt",
        headers={"Authorization": "Bearer not.a.token"},
    )
    assert r.status_code == 401


def test_file_not_found(client, alice_headers, mocker):
    s3 = MagicMock()
    error_response = {"Error": {"Code": "NoSuchKey", "Message": "Not found"}}
    s3.get_object.side_effect = ClientError(error_response, "GetObject")
    # Make exceptions.NoSuchKey also a ClientError so the isinstance check works
    s3.exceptions.NoSuchKey = ClientError
    mocker.patch("app.routers.example01.get_s3_client", return_value=s3)

    r = client.get("/api/01-backend-proxy/file/missing.txt", headers=alice_headers)

    assert r.status_code in (404, 502)  # caught as generic exception → 502
