#!/usr/bin/env bash
# test-access.sh — End-to-end access-control checks for examples 01–03.
#
# Required environment variables:
#   GATEWAY_URL   Base URL of the Envoy Gateway (e.g. http://localhost:80)
#
# Usage:
#   GATEWAY_URL=http://localhost:80 ./test-access.sh

set -euo pipefail

GATEWAY_URL="${GATEWAY_URL:?Set GATEWAY_URL to the gateway base URL, e.g. http://localhost:80}"

PASS="✓"
FAIL="✗"
FAILURES=0

# ── Token acquisition via login endpoint ────────────────────────────────────

_login() {
  local username="$1"
  local password="$2"
  local resp
  resp=$(curl -s -X POST "$GATEWAY_URL/api/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$username\",\"password\":\"$password\"}" \
    --max-time 10) || true
  # Extract access_token value from JSON without requiring jq
  echo "$resp" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4
}

echo "Logging in as alice via $GATEWAY_URL/api/login ..."
ALICE_TOKEN=$(_login "alice" "alice")
if [ -z "$ALICE_TOKEN" ]; then
  echo "ERROR: Could not obtain alice's token. Is GATEWAY_URL reachable?" >&2
  exit 1
fi

echo "Logging in as bob via $GATEWAY_URL/api/login ..."
BOB_TOKEN=$(_login "bob" "bob")
if [ -z "$BOB_TOKEN" ]; then
  echo "ERROR: Could not obtain bob's token. Is GATEWAY_URL reachable?" >&2
  exit 1
fi

# ── Helpers ─────────────────────────────────────────────────────────────────

_http_status() {
  curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$@" || echo "ERR"
}

_check_status() {
  local desc="$1"
  local want="$2"
  shift 2
  local got
  got=$(_http_status "$@")
  if [ "$got" = "$want" ]; then
    printf "  %s %s\n" "$PASS" "$desc"
  else
    printf "  %s %s  (expected HTTP %s, got %s)\n" "$FAIL" "$desc" "$want" "$got"
    FAILURES=$((FAILURES + 1))
  fi
}

# Passes on 2xx / 3xx only. Fails on any 4xx, 5xx, or connection error.
_check_allowed() {
  local desc="$1"
  shift
  local got
  got=$(_http_status "$@")
  case "$got" in
    2*|3*)
      printf "  %s %s  (HTTP %s)\n" "$PASS" "$desc" "$got"
      ;;
    ERR)
      printf "  %s %s  (request failed / timeout)\n" "$FAIL" "$desc"
      FAILURES=$((FAILURES + 1))
      ;;
    *)
      printf "  %s %s  (unexpected HTTP %s)\n" "$FAIL" "$desc" "$got"
      FAILURES=$((FAILURES + 1))
      ;;
  esac
}

AUTH_ALICE=(-H "Authorization: Bearer $ALICE_TOKEN")
AUTH_BOB=(-H "Authorization: Bearer $BOB_TOKEN")

echo ""
echo "Gateway: $GATEWAY_URL"
echo ""

# ── Example 01 — Backend Proxy ───────────────────────────────────────────────
# The backend validates the JWT and always fetches from the authenticated
# user's own bucket. No token → 403 (HTTPBearer). Bob is authenticated but
# only reaches his own bucket (bob-bucket), not alice's.
echo "## Example 01 — Backend Proxy"
_check_status \
  "Not authenticated (no token) is rejected" \
  "401" \
  "$GATEWAY_URL/api/01-backend-proxy/file/alice.txt"

# Bob is authenticated; the backend serves bob-bucket instead of alice-bucket.
# alice.txt does not exist in bob-bucket, so the backend returns 404 — proving
# bob cannot read alice's files even with a valid JWT.
_check_status \
  "Authenticated but not authorized (bob) cannot access alice's data" \
  "404" \
  "$GATEWAY_URL/api/01-backend-proxy/file/alice.txt" \
  "${AUTH_BOB[@]}"

# A 404 is acceptable: auth succeeded, but the file may not exist in alice-bucket.
_check_allowed \
  "Authenticated and authorized (alice) is accepted" \
  "$GATEWAY_URL/api/01-backend-proxy/file/alice.txt" \
  "${AUTH_ALICE[@]}"

echo ""

# ── Example 02 — Gateway Auth (Envoy ext-authz) ──────────────────────────────
# The SecurityPolicy intercepts every request and calls the authz endpoint.
# The authz endpoint returns 403 for a missing JWT, blocking the request.
# Any valid JWT (including bob's) passes authz and is forwarded to S3.
echo "## Example 02 — Gateway Auth (ext-authz)"
_check_status \
  "Not authenticated (no token) is rejected" \
  "403" \
  "$GATEWAY_URL/api/02-gateway-auth/s3/alice-bucket/alice.txt"

# Bob's valid JWT passes the authz check; S3 access depends on bucket policies.
_check_allowed \
  "Authenticated but not authorized (bob) reaches S3 — authz is JWT-only" \
  "$GATEWAY_URL/api/02-gateway-auth/s3/alice-bucket/alice.txt" \
  "${AUTH_BOB[@]}"

# Auth succeeds; actual status depends on whether the S3 object exists.
_check_allowed \
  "Authenticated and authorized (alice) is accepted" \
  "$GATEWAY_URL/api/02-gateway-auth/s3/alice-bucket/alice.txt" \
  "${AUTH_ALICE[@]}"

echo ""

# ── Example 03 — Presigned URL ───────────────────────────────────────────────
# Same JWT flow as example 01. On success the backend returns a 302 redirect
# to a short-lived presigned S3 URL for the authenticated user's own bucket.
# Bob is authenticated but only gets a presigned URL for bob-bucket, not alice's.
echo "## Example 03 — Presigned URL"
_check_status \
  "Not authenticated (no token) is rejected" \
  "401" \
  "$GATEWAY_URL/api/03-presigned-uri/file/alice.txt"

# Bob is authenticated; the backend generates a presigned URL for bob-bucket.
_check_status \
  "Authenticated but not authorized (bob) cannot access alice's data" \
  "302" \
  "$GATEWAY_URL/api/03-presigned-uri/file/alice.txt" \
  "${AUTH_BOB[@]}"

# Backend generates a presigned URL for alice-bucket and returns a 302 redirect.
_check_status \
  "Authenticated and authorized (alice) is accepted" \
  "302" \
  "$GATEWAY_URL/api/03-presigned-uri/file/alice.txt" \
  "${AUTH_ALICE[@]}"

echo ""

# ── Summary ──────────────────────────────────────────────────────────────────
if [ "$FAILURES" -eq 0 ]; then
  echo "All checks passed."
else
  echo "$FAILURES check(s) failed."
  exit 1
fi
