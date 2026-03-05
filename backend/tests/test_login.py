import jwt
import pytest


def test_login_alice(client):
    r = client.post("/api/login", json={"username": "alice", "password": "alice"})
    assert r.status_code == 200
    data = r.json()
    assert data["token_type"] == "bearer"
    payload = jwt.decode(data["access_token"], options={"verify_signature": False})
    assert payload["sub"] == "alice"


def test_login_bob(client):
    r = client.post("/api/login", json={"username": "bob", "password": "bob"})
    assert r.status_code == 200
    payload = jwt.decode(r.json()["access_token"], options={"verify_signature": False})
    assert payload["sub"] == "bob"


def test_login_wrong_password(client):
    r = client.post("/api/login", json={"username": "alice", "password": "wrong"})
    assert r.status_code == 401


def test_login_unknown_user(client):
    r = client.post("/api/login", json={"username": "eve", "password": "eve"})
    assert r.status_code == 401
