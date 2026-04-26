#!/bin/bash
set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <namespace>"
    exit 1
fi

NAMESPACE="$1"
HOMELAB_CONTEXT="default"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

kubectl config use-context $HOMELAB_CONTEXT
kubectl apply -f "$REPO_ROOT/apps/$NAMESPACE/namespace.yaml"
$SCRIPT_DIR/secrets.sh "$NAMESPACE"

# Apps still on the legacy in-pod tailscale sidecar pattern have an rbac.yaml.
# Apps migrated to the Tailscale operator do not, and they do not need a per-app
# auth key. Detect which pattern this app uses.
if [ -f "$REPO_ROOT/apps/$NAMESPACE/rbac.yaml" ]; then
    $SCRIPT_DIR/tailscale-authkey.sh "$NAMESPACE"
fi

kubectl apply -k "$REPO_ROOT/apps/$NAMESPACE"
