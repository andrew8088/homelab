#!/bin/bash
set -e

HOMELAB_CONTEXT="homelab"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🚀 Deploying to homelab cluster..."

# Ensure we're using the right context
kubectl config use-context $HOMELAB_CONTEXT

# Deploy infrastructure first
echo "📦 Deploying infrastructure..."
kubectl apply -f "$REPO_ROOT/infrastructure/storage/"

# Deploy applications
echo "🎯 Deploying applications..."
for app_dir in "$REPO_ROOT/apps"/*; do
    if [ -d "$app_dir" ] && [ -f "$app_dir/kustomization.yaml" ]; then
        app_name=$(basename "$app_dir")
        echo "  → Deploying $app_name"
        kubectl apply -k "$app_dir"
    fi
done

echo "✅ Deployment complete!"
kubectl get pods -A
