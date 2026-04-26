#!/bin/bash

# Tailscale Reset Script
# Resets Tailscale state and restarts pods after homelab restart
# Usage: ./scripts/tailscale-reset.sh [--sync-secrets]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$(dirname "$SCRIPT_DIR")/apps"

# Apps that use Tailscale sidecars
TAILSCALE_APPS=(
    freshrss
    homeassistant
    jellyfin
)

SYNC_SECRETS=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --sync-secrets)
            SYNC_SECRETS=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--sync-secrets]"
            echo ""
            echo "Resets Tailscale state for all apps and restarts deployments."
            echo ""
            echo "Options:"
            echo "  --sync-secrets  Sync tailscale-auth from 1Password first"
            echo "                  (use after generating a new auth key)"
            echo ""
            echo "Run this script after homelab restarts if Tailscale pods are in CrashLoopBackOff."
            exit 0
            ;;
    esac
done

echo "🔄 Tailscale Reset Script"
echo "========================="

# Sync secrets from 1Password if requested
if [ "$SYNC_SECRETS" = true ]; then
    echo ""
    echo "📦 Syncing tailscale-auth from 1Password..."
    for app in "${TAILSCALE_APPS[@]}"; do
        if [ -d "$APPS_DIR/$app" ]; then
            echo "  → $app"
            "$SCRIPT_DIR/secrets.sh" "$app" 2>/dev/null || echo "    ⚠️  No secrets tagged for $app"
        fi
    done
fi

echo ""
echo "🗑️  Clearing Tailscale state secrets..."
for app in "${TAILSCALE_APPS[@]}"; do
    if kubectl get namespace "$app" >/dev/null 2>&1; then
        echo "  → $app"
        kubectl delete secret tailscale-state -n "$app" --ignore-not-found
        kubectl apply -f "$APPS_DIR/$app/secrets.yaml" 2>/dev/null || \
            kubectl create secret generic tailscale-state -n "$app" --dry-run=client -o yaml | kubectl apply -f -
    else
        echo "  → $app (namespace not found, skipping)"
    fi
done

echo ""
echo "🚀 Restarting deployments..."
for app in "${TAILSCALE_APPS[@]}"; do
    if kubectl get namespace "$app" >/dev/null 2>&1; then
        # Find deployments in the namespace (exclude postgres, redis, samba)
        deployments=$(kubectl get deployments -n "$app" --no-headers -o custom-columns=":metadata.name" 2>/dev/null | grep -v -E "^(postgres|redis|samba)$" || true)
        for deploy in $deployments; do
            echo "  → $app/$deploy"
            kubectl rollout restart deployment "$deploy" -n "$app"
        done
    fi
done

echo ""
echo "⏳ Waiting for rollouts to complete..."
for app in "${TAILSCALE_APPS[@]}"; do
    if kubectl get namespace "$app" >/dev/null 2>&1; then
        deployments=$(kubectl get deployments -n "$app" --no-headers -o custom-columns=":metadata.name" 2>/dev/null | grep -v -E "^(postgres|redis|samba)$" || true)
        for deploy in $deployments; do
            kubectl rollout status deployment "$deploy" -n "$app" --timeout=120s || echo "  ⚠️  $app/$deploy did not become ready"
        done
    fi
done

echo ""
echo "✅ Done! Checking pod status..."
echo ""
kubectl get pods -A | grep -E "^($(IFS=\|; echo "${TAILSCALE_APPS[*]}"))\s"
