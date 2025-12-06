#!/bin/bash

# Generate a fresh Tailscale auth key for a namespace
# Usage: ./tailscale-authkey.sh <namespace> [hostname]

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <namespace> [hostname]"
    echo "Example: $0 maybe"
    echo "Example: $0 copyparty copyparty"
    exit 1
fi

NAMESPACE="$1"
HOSTNAME="${2:-$NAMESPACE}"  # Default hostname to namespace name

echo "🔐 Generating Tailscale auth key for namespace: $NAMESPACE (hostname: $HOSTNAME)"

# Get Tailscale API key from 1Password
echo "📥 Retrieving Tailscale API key from 1Password..."
TAILSCALE_API_KEY=$(op item get "tailscale-api-key" --vault homelab --fields api_key --reveal 2>/dev/null)

if [ -z "$TAILSCALE_API_KEY" ]; then
    echo "❌ Error: Could not retrieve Tailscale API key from 1Password"
    echo "Make sure you've created the 'tailscale-api-key' item in the homelab vault"
    exit 1
fi

# Get tailnet from current tailscale status
TAILNET=$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.[^.]*$//' | sed 's/^[^.]*\.//')

if [ -z "$TAILNET" ]; then
    echo "⚠️  Could not detect tailnet, using default format"
    TAILNET="twin-barley.ts.net"
fi

echo "🌐 Tailnet: $TAILNET"

# Generate auth key via Tailscale API
echo "🔑 Generating new auth key via Tailscale API..."
AUTH_KEY=$(curl -s -X POST "https://api.tailscale.com/api/v2/tailnet/$TAILNET/keys" \
    -H "Authorization: Bearer $TAILSCALE_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"capabilities\": {
            \"devices\": {
                \"create\": {
                    \"reusable\": false,
                    \"ephemeral\": true,
                    \"preauthorized\": true,
                    \"tags\": [\"tag:k3s\"]
                }
            }
        },
        \"expirySeconds\": 7776000,
        \"description\": \"k3s-$NAMESPACE-$(date +%Y%m%d-%H%M%S)\"
    }" | jq -r '.key')

if [ -z "$AUTH_KEY" ] || [ "$AUTH_KEY" = "null" ]; then
    echo "❌ Error: Failed to generate auth key"
    echo "Check that your API key has the correct permissions"
    exit 1
fi

echo "✅ Auth key generated"

# Update or create the Kubernetes secret
echo "📝 Updating Kubernetes secret in namespace: $NAMESPACE..."

if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    kubectl create secret generic tailscale-auth \
        --namespace="$NAMESPACE" \
        --from-literal=TS_AUTHKEY="$AUTH_KEY" \
        --dry-run=client -o yaml | kubectl apply -f -

    echo "✅ Successfully updated tailscale-auth secret in namespace: $NAMESPACE"
    echo ""
    echo "🚀 You can now deploy or restart your application:"
    echo "   kubectl apply -k apps/$NAMESPACE/"
    echo "   kubectl rollout restart deployment -n $NAMESPACE"
else
    echo "⚠️  Namespace $NAMESPACE does not exist yet"
    echo "The secret will be created when you run: kubectl apply -k apps/$NAMESPACE/"
fi

echo ""
echo "ℹ️  Note: This is a single-use, ephemeral auth key that expires in 90 days"
