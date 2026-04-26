# Homelab K3s Application Deployment Patterns

This document outlines the established patterns and practices for deploying applications in the homelab K3s cluster.

## Repository Structure

```
homelab/
├── apps/
│   ├── tailscale-operator/  # Cluster-wide Tailscale operator install
│   ├── maybe/               # Reference implementation (operator pattern)
│   └── [other-apps]/        # Some still on the legacy sidecar pattern
└── scripts/
    ├── deploy.sh            # Main deployment script
    └── secrets.sh           # 1Password secrets sync
```

## Tailscale: Operator Pattern

External access for every app is provided by the [Tailscale Kubernetes Operator](https://tailscale.com/kb/1236/kubernetes-operator), installed once cluster-wide. Each app gets its own machine on the tailnet by declaring an Ingress (for HTTPS) or a Service (for raw TCP) with the `tailscale` class — the operator spins up a proxy pod in the `tailscale` namespace that joins the tailnet with the app's hostname.

Install or upgrade the operator with `apps/tailscale-operator/install.sh`. The script's header documents the one-time tailnet ACL and 1Password OAuth setup.

### Exposing an app over HTTPS

Add a ClusterIP `Service` and an `Ingress` with `ingressClassName: tailscale`. The hostname comes from the Ingress `metadata.name` (override with the `tailscale.com/hostname` annotation):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: maybe
  namespace: maybe
spec:
  selector:
    app: maybe
  ports:
  - port: 80
    targetPort: 3000
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: maybe
  namespace: maybe
spec:
  ingressClassName: tailscale
  defaultBackend:
    service:
      name: maybe
      port:
        number: 80
  tls:
  - hosts:
    - maybe
```

This makes the app reachable at `https://maybe.<tailnet>.ts.net` with a Tailscale-issued certificate.

### Exposing an app over raw TCP

Use a `Service` of type `LoadBalancer` with `loadBalancerClass: tailscale` and a `tailscale.com/hostname` annotation.

## Standard Application Structure

Each application in `apps/` follows this structure:

### Required Files

1. **`kustomization.yaml`**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
  - ingress.yaml
```

2. **`namespace.yaml`** — dedicated namespace
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: app-name
```

3. **`deployment.yaml`** — application pods. No tailscale sidecar, no `serviceAccountName: tailscale`.

4. **`service.yaml`** — ClusterIP service the Ingress targets.

5. **`ingress.yaml`** — Tailscale Ingress (see template above).

### Optional Components

- **`postgres.yaml`** / **`redis.yaml`** — database dependencies
- **`pvc.yaml`** — Persistent Volume Claims (prefer hostPath volumes)
- **`*-config.yaml`** — application-specific ConfigMaps

## Deployment Patterns

### Container Standards

1. **Resource Constraints** — all containers must have requests and limits.
2. **Health Checks** — include both liveness and readiness probes.
3. **Init Containers** — use for dependency waiting (e.g. `pg_isready` loop).

### Storage Pattern

Use hostPath volumes for persistent data:

```yaml
volumes:
- name: app-data
  hostPath:
    path: /mnt/primary/k3s-storage/app-name-data
    type: DirectoryOrCreate
```

### Database Dependencies

For apps requiring databases, create separate deployments with services. Each database should have a deployment with resource limits, a persistent hostPath volume, health checks, and a ClusterIP service. See `apps/maybe/postgres.yaml` and `apps/maybe/redis.yaml`.

## Secret Management

Secrets are managed via 1Password CLI integration:

1. Store secrets in 1Password with vault `homelab`.
2. Tag secrets with the target namespace name.
3. Run `./scripts/secrets.sh <namespace>` (called automatically by `deploy.sh`).
4. The script compares timestamps and only updates when the 1Password item is newer than the in-cluster secret.

Cluster-wide secrets:
- `tailscale-operator-oauth` (1Password only) — operator OAuth client; consumed by `apps/tailscale-operator/install.sh`.

## Deployment Process

```bash
# Deploy or update one app
./scripts/deploy.sh <namespace>

# Or deploy without re-syncing secrets / context switch
kubectl apply -k apps/<namespace>/
```

## Creating New Applications

1. `mkdir apps/new-app`
2. Copy `namespace.yaml`, `deployment.yaml`, `service.yaml`, `ingress.yaml`, `kustomization.yaml` from `apps/maybe/` and adjust names, ports, image, and the Ingress hostname.
3. Add any database deployments, ConfigMaps, or PVCs the app needs.
4. Add app secrets to 1Password (vault `homelab`, tagged with the namespace name).
5. `./scripts/deploy.sh new-app`

## Reference Application

- **`apps/maybe/`** — full-stack Rails app with Postgres, Redis, worker container, and Tailscale operator Ingress. Use as the template for new apps.

## Legacy Sidecar Pattern (deprecated)

A handful of apps (`freshrss`, `homeassistant`, `jellyfin`) still run an in-pod `tailscale` sidecar with a per-namespace `rbac.yaml`, `serve-config.yaml`, and `tailscale-state` secret. These will be migrated to the operator pattern over time. Until then, `scripts/tailscale-authkey.sh` and `scripts/tailscale-reset.sh` continue to support them, and `deploy.sh` auto-detects the legacy pattern by the presence of `rbac.yaml`.

## Best Practices

1. Always use resource limits.
2. Include health checks.
3. Use init containers for dependency waiting.
4. One namespace per app.
5. Expose externally only via the Tailscale operator — never `Service type=NodePort` or `type=LoadBalancer` without the `tailscale` class.
6. Document complex app config in ConfigMaps.
