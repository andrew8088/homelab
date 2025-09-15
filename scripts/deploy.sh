#!/bin/bash
set -ex

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
kubectl apply -k "$REPO_ROOT/apps/$NAMESPACE"
