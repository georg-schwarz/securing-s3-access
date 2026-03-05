"""
Example 02 — Gateway auth (Envoy ext-authz style).

The endpoint validates the JWT and returns 200 + x-user header or 403.
"""


def test_valid_token_returns_200_with_user_header(client, alice_token):
    r = client.get(
        "/api/02-gateway-auth/authz",
        headers={"Authorization": f"Bearer {alice_token}"},
    )
    assert r.status_code == 200
    assert r.headers["x-user"] == "alice"


def test_valid_bob_token(client, bob_token):
    r = client.get(
        "/api/02-gateway-auth/authz",
        headers={"Authorization": f"Bearer {bob_token}"},
    )
    assert r.status_code == 200
    assert r.headers["x-user"] == "bob"


def test_no_auth_header_returns_403(client):
    r = client.get("/api/02-gateway-auth/authz")
    assert r.status_code == 403


def test_invalid_token_returns_403(client):
    r = client.get(
        "/api/02-gateway-auth/authz",
        headers={"Authorization": "Bearer this.is.garbage"},
    )
    assert r.status_code == 403


def test_malformed_header_returns_403(client):
    r = client.get(
        "/api/02-gateway-auth/authz",
        headers={"Authorization": "Basic dXNlcjpwYXNz"},
    )
    assert r.status_code == 403


def test_expired_token_returns_403(client):
    from datetime import datetime, timedelta, timezone

    import jwt

    token = jwt.encode(
        {"sub": "alice", "exp": datetime.now(timezone.utc) - timedelta(seconds=1)},
        "test-secret",
        algorithm="HS256",
    )
    r = client.get(
        "/api/02-gateway-auth/authz",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 403
