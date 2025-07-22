# Homelab K8s Apps

## Setup
```bash
make setup    # Create namespaces and secrets
make deploy   # Deploy applications
make status   # Check deployment status
Home Assistant

Access at http://<node-ip>:8123
Config persisted in PVC
Uses host network for device discovery

Secrets
See secrets/secret-refs.md for 1Password setup requirements.
