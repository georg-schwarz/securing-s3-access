from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from botocore.credentials import Credentials
from fastapi import APIRouter, Request, Response

from app.auth import decode_token
from app.s3 import S3_ACCESS_KEY, S3_ENDPOINT, S3_REGION, S3_SECRET_KEY

router = APIRouter()

_AUTHZ_S3_PREFIX = "/api/02-gateway-auth/s3"
_S3_HOST = S3_ENDPOINT.split("://", 1)[-1]  # e.g. garage-instance.default.svc.cluster.local:3900


def _sigv4_headers(s3_path: str) -> dict:
    """Return SigV4 Authorization, X-Amz-Date, and X-Amz-Content-Sha256 headers."""
    creds = Credentials(S3_ACCESS_KEY, S3_SECRET_KEY)
    req = AWSRequest(method="GET", url=f"{S3_ENDPOINT}{s3_path}")
    req.headers["Host"] = _S3_HOST
    SigV4Auth(creds, "s3", S3_REGION).add_auth(req)
    return {
        "Authorization": req.headers["Authorization"],
        "X-Amz-Date": req.headers["X-Amz-Date"],
        "X-Amz-Content-Sha256": req.headers.get(
            "X-Amz-Content-Sha256",
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        ),
    }


@router.get("/api/02-gateway-auth/authz{remainder:path}")
def authz(request: Request, remainder: str = ""):
    """
    Envoy external authorization endpoint.

    Envoy's extAuth.http.path acts as a prefix: it prepends the configured path
    to the original request :path before calling this endpoint. So a request for
    /api/02-gateway-auth/s3/alice-bucket/alice.txt arrives here as:
      GET /api/02-gateway-auth/authz/api/02-gateway-auth/s3/alice-bucket/alice.txt
    The `remainder` parameter captures the appended original path.

    We validate the JWT, strip the route prefix from `remainder` to get the S3
    object path (/alice-bucket/alice.txt), and compute SigV4 credentials signed
    for that path against the Garage S3 endpoint.

    Envoy forwards the SigV4 headers listed in SecurityPolicy headersToBackend
    to Garage, overriding the original Bearer token in the Authorization header.
    """
    auth_header = request.headers.get("authorization", "")
    if not auth_header.lower().startswith("bearer "):
        return Response(status_code=403)

    token = auth_header[len("bearer "):]
    try:
        username = decode_token(token)
    except Exception:
        return Response(status_code=403)

    s3_path = remainder[len(_AUTHZ_S3_PREFIX):] if remainder.startswith(_AUTHZ_S3_PREFIX) else "/"

    return Response(
        status_code=200,
        headers={"x-user": username, **_sigv4_headers(s3_path)},
    )
