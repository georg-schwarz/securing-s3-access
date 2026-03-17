#!/usr/bin/env bash
# uninstall.sh — Remove all tutorial releases and clean up stuck resources.
#
# Usage:
#   ./uninstall.sh

set -euo pipefail

log()  { echo "    $*"; }
step() { echo; echo "=== $* ==="; }

cleanup_stale_gatewayclass() {
  local gc_name="$1"
  local deletion_ts
  local gateways
  local finalizers

  deletion_ts=$(kubectl get gatewayclass "$gc_name" \
    -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || true)
  [ -n "$deletion_ts" ] || return 0

  step "Cleaning up stale GatewayClass $gc_name"

  gateways=$(kubectl get gateway -A \
    -o jsonpath="{range .items[?(@.spec.gatewayClassName=='$gc_name')]}{.metadata.namespace}/{.metadata.name}{'\\n'}{end}" 2>/dev/null || true)

  if [ -n "$gateways" ]; then
    log "Deleting Gateways still referencing '$gc_name'..."
    while IFS=/ read -r namespace name; do
      [ -n "$namespace" ] || continue
      kubectl delete gateway "$name" -n "$namespace" --ignore-not-found=true >/dev/null || true
    done <<< "$gateways"

    kubectl wait --for=delete gateway -A \
      -l gateway.networking.k8s.io/gateway-class-name="$gc_name" --timeout=60s >/dev/null 2>&1 || true
  fi

  finalizers=$(kubectl get gatewayclass "$gc_name" \
    -o jsonpath='{.metadata.finalizers[*]}' 2>/dev/null || true)

  if [ -n "$finalizers" ]; then
    log "Removing stale finalizers from GatewayClass '$gc_name'..."
    kubectl patch gatewayclass "$gc_name" --type=merge \
      -p '{"metadata":{"finalizers":[]}}' >/dev/null
  fi

  log "Waiting for GatewayClass '$gc_name' to be deleted..."
  kubectl wait --for=delete gatewayclass/"$gc_name" --timeout=60s >/dev/null 2>&1 || true
}

cleanup_stale_namespaced_resource() {
  local kind="$1"
  local name="$2"
  local namespace="$3"
  local deletion_ts
  local finalizers

  deletion_ts=$(kubectl get "$kind" "$name" -n "$namespace" \
    -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || true)
  [ -n "$deletion_ts" ] || return 0

  step "Cleaning up stale $kind $namespace/$name"

  finalizers=$(kubectl get "$kind" "$name" -n "$namespace" \
    -o jsonpath='{.metadata.finalizers[*]}' 2>/dev/null || true)

  if [ -n "$finalizers" ]; then
    log "Removing stale finalizers from $kind/$name..."
    kubectl patch "$kind" "$name" -n "$namespace" --type=merge \
      -p '{"metadata":{"finalizers":[]}}' >/dev/null
  fi

  log "Waiting for $kind/$name to be deleted..."
  kubectl wait --for=delete "$kind/$name" -n "$namespace" --timeout=60s >/dev/null 2>&1 || true
}

step "Uninstalling tutorial releases"
for release in \
  example-03-presigned-url \
  example-02-gateway-auth \
  example-01-backend-proxy \
  garage-instance \
  garage-operator \
  envoy-ingress
do
  log "Uninstalling Helm release '$release' if present..."
  helm uninstall "$release" -n default --ignore-not-found >/dev/null 2>&1 || true
done

step "Removing leftover hook resources"
kubectl delete job garage-instance-post-install -n default --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
kubectl delete pod -n default -l job-name=garage-instance-post-install --ignore-not-found=true --wait=false >/dev/null 2>&1 || true

step "Removing leftover Envoy data-plane resources"
GW_RESOURCE_LABELS="gateway.envoyproxy.io/owning-gateway-name=envoy-ingress,gateway.envoyproxy.io/owning-gateway-namespace=default"
kubectl delete service,deployment,replicaset,pod -n default -l "$GW_RESOURCE_LABELS" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true

step "Deleting leftover custom resources"
kubectl delete garagebucket alice-bucket bob-bucket -n default --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
kubectl delete garagekey garage-instance-backend-key -n default --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
kubectl delete garagecluster garage-instance -n default --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
kubectl delete gateway envoy-ingress -n default --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
kubectl delete gatewayclass eg --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
kubectl delete secret garage-instance-admin-token garage-instance-backend-key -n default --ignore-not-found=true --wait=false >/dev/null 2>&1 || true

cleanup_stale_namespaced_resource garagebucket alice-bucket default
cleanup_stale_namespaced_resource garagebucket bob-bucket default
cleanup_stale_namespaced_resource garagekey garage-instance-backend-key default
cleanup_stale_namespaced_resource garagecluster garage-instance default
cleanup_stale_gatewayclass eg

step "Uninstall complete"
echo
echo "  Tutorial releases have been removed."
echo "  If you want a fresh environment, run: ./install.sh"
echo
