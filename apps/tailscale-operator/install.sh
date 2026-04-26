#!/bin/bash
#
# Install or upgrade the Tailscale Kubernetes Operator.
#
# One-time setup before running this script:
#
#   1. In the Tailscale admin console, edit the ACL to declare a tag owner:
#
#        "tagOwners": {
#          "tag:k8s": ["autogroup:admin"]
#        }
#
#   2. In the Tailscale admin console, create an OAuth client with write scopes:
#        - Devices Core (write)
#        - Auth Keys (write)
#      Tag it with: tag:k8s
#      (Both scopes need tag:k8s in their per-scope tag picker.)
#
#   3. Store the OAuth client in 1Password (vault: homelab) as item
#      "tailscale-operator-oauth" with two fields:
#        - clientId
#        - clientSecret
#
#   4. Run this script.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "📥 Retrieving OAuth credentials from 1Password..."
CLIENT_ID=$(op item get "tailscale-operator-oauth" --vault homelab --fields clientId --reveal 2>/dev/null)
CLIENT_SECRET=$(op item get "tailscale-operator-oauth" --vault homelab --fields clientSecret --reveal 2>/dev/null)

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    echo "❌ Could not retrieve OAuth credentials from 1Password."
    echo "   Create item 'tailscale-operator-oauth' in vault 'homelab' with fields"
    echo "   'client_id' and 'client_secret'. See header of this script for setup."
    exit 1
fi

echo "📦 Adding/updating Tailscale Helm repo..."
helm repo add tailscale https://pkgs.tailscale.com/helmcharts >/dev/null 2>&1 || true
helm repo update tailscale >/dev/null

echo "🚀 Installing/upgrading tailscale-operator..."
helm upgrade --install tailscale-operator tailscale/tailscale-operator \
    --namespace=tailscale \
    --create-namespace \
    --set-string oauth.clientId="$CLIENT_ID" \
    --set-string oauth.clientSecret="$CLIENT_SECRET" \
    --values "$SCRIPT_DIR/values.yaml"

echo ""
echo "✅ Done. Verify the operator is running:"
echo "   kubectl get pods -n tailscale"
