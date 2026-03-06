from fastapi import APIRouter, Request, Response

from app.auth import decode_token

router = APIRouter()


@router.get("/api/02-gateway-auth/authz{remainder:path}")
def authz(request: Request, remainder: str = ""):
    """
    Envoy external authorization endpoint.

    Envoy passes the original request headers. We validate the JWT from the
    Authorization header and return 200 (allow) or 403 (deny).

    We also inject an x-user header so the upstream can trust the identity
    without re-validating the JWT.
    """
    auth_header = request.headers.get("authorization", "")
    if not auth_header.lower().startswith("bearer "):
        return Response(status_code=403)

    token = auth_header[len("bearer "):]
    try:
        username = decode_token(token)
    except Exception:
        return Response(status_code=403)

    return Response(
        status_code=200,
        headers={"x-user": username},
    )
