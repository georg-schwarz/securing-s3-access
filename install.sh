#!/usr/bin/env bash
# install.sh — Install all Helm charts in the correct order and run tests.
#
# Prerequisites: kubectl, helm, and a local Kubernetes cluster
#
# Usage:
#   ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_DIR="$SCRIPT_DIR/helm"
KUBE_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"

log()  { echo "    $*"; }
step() { echo; echo "=== $* ==="; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ── 0. Helm dependencies ──────────────────────────────────────────────────────
step "Building Helm chart dependencies"
helm dependency build "$HELM_DIR/envoy-ingress"
helm dependency build "$HELM_DIR/garage-operator"

# ── 1. Envoy Gateway ────────────────────────────────────────────────────────
step "Installing Envoy Gateway"

helm upgrade --install envoy-ingress "$HELM_DIR/envoy-ingress" \
  --namespace default \
  --wait --timeout=5m

log "Waiting for Envoy Gateway controller deployment..."
kubectl rollout status deployment/envoy-gateway \
  -n default --timeout=3m

# ── 2. Garage Operator ───────────────────────────────────────────────────────
step "Installing Garage Operator"
helm upgrade --install garage-operator "$HELM_DIR/garage-operator" \
  --namespace default \
  --wait --timeout=5m

log "Waiting for Garage Operator deployment..."
kubectl rollout status deployment \
  -l app.kubernetes.io/instance=garage-operator \
  -n default --timeout=3m

# ── 3. Garage Instance (with demo buckets) ───────────────────────────────────
step "Installing Garage Instance"

helm upgrade --install garage-instance "$HELM_DIR/garage-instance" \
  --namespace default \
  --timeout=10m

log "Waiting for GarageCluster to reach Running..."
kubectl wait garagecluster/garage-instance -n default \
  --for=jsonpath='{.status.phase}'=Running --timeout=5m

log "Waiting for GarageBuckets to become Ready..."
kubectl wait garagebucket/alice-bucket garagebucket/bob-bucket -n default \
  --for=jsonpath='{.status.phase}'=Ready --timeout=3m

log "Waiting for GarageKey to become Ready..."
kubectl wait garagekey/garage-instance-backend-key -n default \
  --for=jsonpath='{.status.phase}'=Ready --timeout=3m

log "Post-install seed job completed (run by Helm as a post-install hook)."

# ── Extract S3 credentials ───────────────────────────────────────────────────
step "Extracting S3 credentials"
S3_ACCESS_KEY=$(kubectl get secret garage-instance-backend-key -n default \
  -o jsonpath='{.data.access-key-id}' | base64 -d)
S3_SECRET_KEY=$(kubectl get secret garage-instance-backend-key -n default \
  -o jsonpath='{.data.secret-access-key}' | base64 -d)
log "Credentials extracted."

# ── 4. Example 01 — Backend Proxy ────────────────────────────────────────────
step "Installing Example 01 — Backend Proxy"
helm upgrade --install example-01-backend-proxy "$HELM_DIR/examples/01-backend-proxy" \
  --namespace default \
  --set backend.s3AccessKeyId="$S3_ACCESS_KEY" \
  --set backend.s3SecretAccessKey="$S3_SECRET_KEY"

kubectl rollout status deployment/example-01-backend-proxy \
  -n example-01 --timeout=3m

# ── 5. Example 02 — Gateway Auth ─────────────────────────────────────────────
step "Installing Example 02 — Gateway Auth"
helm upgrade --install example-02-gateway-auth "$HELM_DIR/examples/02-gateway-auth" \
  --namespace default \
  --set backend.s3AccessKeyId="$S3_ACCESS_KEY" \
  --set backend.s3SecretAccessKey="$S3_SECRET_KEY"

kubectl rollout status deployment/example-02-gateway-auth \
  -n example-02 --timeout=3m

# ── 6. Example 03 — Presigned URL ────────────────────────────────────────────
step "Installing Example 03 — Presigned URL"
helm upgrade --install example-03-presigned-url "$HELM_DIR/examples/03-presigned-url" \
  --namespace default \
  --set backend.s3AccessKeyId="$S3_ACCESS_KEY" \
  --set backend.s3SecretAccessKey="$S3_SECRET_KEY"

kubectl rollout status deployment/example-03-presigned-url \
  -n example-03 --timeout=3m

# ── Wait for Gateway LoadBalancer IP ─────────────────────────────────────────
step "Waiting for Gateway external IP"

if [ "$KUBE_CONTEXT" = "minikube" ]; then
  echo
  echo "  To expose the LoadBalancer on localhost, run in a separate terminal:"
  echo
  echo "    sudo minikube tunnel"
  echo
  echo "  Waiting up to 5 minutes for the Gateway service to get an external IP..."
  echo "  (start 'minikube tunnel' now if you haven't already)"
  echo
else
  echo
  echo "  Waiting up to 5 minutes for the Gateway service to get an external IP..."
  echo "  Current kubectl context: ${KUBE_CONTEXT:-unknown}"
  echo
fi

GW_SVC_LABELS="gateway.envoyproxy.io/owning-gateway-name=envoy-ingress,gateway.envoyproxy.io/owning-gateway-namespace=default"
GW_SVC_NS="default"

# Wait for the service to be created by the Envoy Gateway controller
GW_SVC_NAME=""
for i in $(seq 1 24); do
  GW_SVC_NAME=$(kubectl get svc -n "$GW_SVC_NS" -l "$GW_SVC_LABELS" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  [ -n "$GW_SVC_NAME" ] && break
  log "Waiting for gateway service to appear... ($i/24)"
  sleep 5
done
[ -n "$GW_SVC_NAME" ] || die "Could not find Envoy Gateway service in $GW_SVC_NS. Check 'kubectl get svc -n $GW_SVC_NS'."

# Wait for the LoadBalancer to receive an external IP
GATEWAY_IP=""
for i in $(seq 1 60); do
  GATEWAY_IP=$(kubectl get svc "$GW_SVC_NAME" -n "$GW_SVC_NS" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [ -n "$GATEWAY_IP" ] && break
  if [ "$KUBE_CONTEXT" = "minikube" ]; then
    log "Waiting for external IP on $GW_SVC_NAME... ($i/60, needs 'minikube tunnel')"
  else
    log "Waiting for external IP on $GW_SVC_NAME... ($i/60)"
  fi
  sleep 5
done

if [ -z "$GATEWAY_IP" ]; then
  if [ "$KUBE_CONTEXT" = "minikube" ]; then
    die "Gateway service never received an external IP. Make sure 'minikube tunnel' is running."
  fi
  die "Gateway service never received an external IP. Check your local cluster's LoadBalancer support."
fi

GATEWAY_URL="http://$GATEWAY_IP"
log "Gateway is reachable at $GATEWAY_URL"

# ── Done ──────────────────────────────────────────────────────────────────────
step "Installation complete"
echo
echo "  All charts are installed and the gateway is reachable."
echo "  To run the end-to-end access-control tests:"
echo
echo "    GATEWAY_URL=\"$GATEWAY_URL\" bash $SCRIPT_DIR/test-access.sh"
echo
