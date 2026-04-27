#!/bin/bash
set -euo pipefail

# Build lira container locally, ship it to the k3s node, and roll out the
# deployment. Safe to run on a fresh cluster (deploy.sh applies manifests
# idempotently) and on every iteration (rollout restart picks up the new
# image since the tag is always :latest with imagePullPolicy: Never).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LIRA_APP_DIR="$REPO_ROOT/../lira-app"

IMAGE_NAME="lira:latest"
K3S_NODE="${K3S_NODE:-k3s-prod}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

if [ ! -d "$LIRA_APP_DIR" ]; then
    error "lira-app directory not found at $LIRA_APP_DIR"
fi

log "Building $IMAGE_NAME in $LIRA_APP_DIR..."
cd "$LIRA_APP_DIR"
docker buildx build -t "$IMAGE_NAME" --platform linux/amd64 .
success "Image built"

log "Transferring image to $K3S_NODE..."
docker save "$IMAGE_NAME" | ssh "$K3S_NODE" "sudo k3s ctr images import -"
success "Image imported to k3s"

log "Applying manifests..."
"$SCRIPT_DIR/deploy.sh" lira
success "Manifests applied"

log "Restarting deployment to pick up new image..."
kubectl rollout restart deployment/lira -n lira
kubectl rollout status deployment/lira -n lira --timeout=120s
success "Deployment restarted"

log "Done! lira is available at https://lira.twin-barley.ts.net"
