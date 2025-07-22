#!/bin/bash
set -euo pipefail

echo "Creating secrets for homelab..."

# Automation namespace
kubectl create namespace automation --dry-run=client -o yaml | kubectl apply -f -

# Home Assistant secrets (add your own secret keys as needed)
kubectl create secret generic homeassistant-secrets \
  --from-literal=secret-key="$(op item get 'homeassistant' --field secret_key)" \
  --from-literal=db-password="$(op item get 'homeassistant-db' --field password)" \
  --namespace=automation \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secrets created successfully"
