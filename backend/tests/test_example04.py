"""
Example 04 — Temporary credentials (placeholder).
"""


def test_returns_not_implemented(client):
    r = client.get("/api/04-temp-credentials/access")
    assert r.status_code == 200
    assert r.json() == {"detail": "not implemented"}
