#!/bin/bash
set -euo pipefail

# Build friday container locally and push to k3s node

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
FRIDAY_APP_DIR="$REPO_ROOT/../friday-app"

IMAGE_NAME="friday:latest"
K3S_NODE="${K3S_NODE:-k3s-prod}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check friday-app directory exists
if [ ! -d "$FRIDAY_APP_DIR" ]; then
    error "friday-app directory not found at $FRIDAY_APP_DIR"
fi

# Build the image
log "Building $IMAGE_NAME in $FRIDAY_APP_DIR..."
cd "$FRIDAY_APP_DIR"
CONTAINER_TOOL="docker buildx" IMAGE_TAG="$IMAGE_NAME" npm run build:container -- --platform linux/amd64
success "Image built"

# Export and transfer to k3s node
log "Transferring image to $K3S_NODE..."
docker save "$IMAGE_NAME" | ssh "$K3S_NODE" "sudo k3s ctr images import -"
success "Image imported to k3s"

# Restart the deployment to pick up new image
log "Restarting friday deployment..."
kubectl rollout restart deployment/friday -n friday
kubectl rollout status deployment/friday -n friday --timeout=120s
success "Deployment restarted"

log "Done! friday is available at https://friday.twin-barley.ts.net"
