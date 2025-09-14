# Homelab K3s Application Deployment Patterns

This document outlines the established patterns and practices for deploying applications in the homelab K3s cluster.

## Repository Structure

```
homelab/
├── apps/                    # Individual application deployments
│   ├── maybe/              # Reference implementation
│   ├── copyparty/          # Reference implementation
│   └── [other-apps]/
└── scripts/               # Deployment and management scripts
    ├── deploy.sh          # Main deployment script
    └── secrets.sh         # 1Password secrets sync
```

## Standard Application Structure

Each application in `apps/` follows this structure:

### Required Files

1. **`kustomization.yaml`** - Lists all Kubernetes resources for the app
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - rbac.yaml
  - secrets.yaml
  - serve-config.yaml
  - deployment.yaml
  # Add optional components as needed
```

2. **`namespace.yaml`** - Dedicated namespace for isolation
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: app-name
```

3. **`deployment.yaml`** - Main application deployment following the multi-container pattern

4. **`rbac.yaml`** - ServiceAccount, Role, and RoleBinding for Tailscale sidecar
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tailscale
  namespace: app-name
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: app-name
  name: tailscale
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["create", "get", "list", "patch", "update", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tailscale
  namespace: app-name
subjects:
- kind: ServiceAccount
  name: tailscale
  namespace: app-name
roleRef:
  kind: Role
  name: tailscale
  apiGroup: rbac.authorization.k8s.io
```

5. **`secrets.yaml`** - Most actual secrets are managed via 1Password, but tailscale needs the `tailscale-state` secret initialized before it starts up.
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: tailscale-state
  namespace: app-name
```

6. **`serve-config.yaml`** - Tailscale serve configuration for external access
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: tailscale-serve-config
  namespace: app-name
data:
  serve.json: |
    {
      "TCP": {
        "443": {
          "HTTPS": true
        }
      },
      "Web": {
        "app-name.twin-barley.ts.net:443": {
          "Handlers": {
            "/": {
              "Proxy": "http://127.0.0.1:PORT"
            }
          }
        }
      }
    }
```

### Optional Components

- **`postgres.yaml`** / **`redis.yaml`** - Database dependencies as separate deployments with services
- **`pvc.yaml`** - Persistent Volume Claims (prefer hostPath volumes)
- **`service.yaml`** - Internal Kubernetes services for pod-to-pod communication
- **`*-config.yaml`** - Application-specific ConfigMaps
- **Additional services** - Like Samba for file sharing (see copyparty example)

## Deployment Patterns

### Multi-Container Architecture

Every application deployment follows this pattern:

```yaml
spec:
  template:
    spec:
      serviceAccountName: tailscale
      initContainers:
      - name: wait-for-dependencies
        # Wait for databases/services to be ready
      containers:
      - name: main-app
        # Primary application container
      - name: worker  # Optional
        # Background job processor (if needed)
      - name: tailscale
        # Secure networking sidecar (required)
```

### Container Standards

1. **Resource Constraints** - All containers must have requests and limits:
```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

2. **Health Checks** - Include both liveness and readiness probes:
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

3. **Init Containers** - Use for dependency waiting:
```yaml
initContainers:
- name: wait-for-postgres
  image: postgres:16
  command: ['sh', '-c']
  args:
  - |
    until pg_isready -h postgres -p 5432 -U user; do
      echo "Waiting for postgres..."
      sleep 2
    done
```

### Tailscale Sidecar Pattern

Every application includes a Tailscale sidecar for secure external access:

```yaml
- name: tailscale
  image: tailscale/tailscale:latest
  env:
  - name: TS_AUTHKEY
    valueFrom:
      secretKeyRef:
        name: tailscale-auth
        key: TS_AUTHKEY
  - name: TS_HOSTNAME
    value: "app-name"
  - name: TS_SERVE_CONFIG
    value: "/config/serve.json"
  - name: TS_STATE_DIR
    value: /tmp
  - name: TS_USERSPACE
    value: "true"
  - name: TS_KUBE_SECRET
    value: "tailscale-state"
  - name: POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  - name: POD_UID
    valueFrom:
      fieldRef:
        fieldPath: metadata.uid
  volumeMounts:
  - name: serve-config
    mountPath: /config
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
  resources:
    requests:
      memory: "64Mi"
      cpu: "50m"
    limits:
      memory: "128Mi"
      cpu: "100m"
```

### Storage Pattern

Use hostPath volumes for persistent data:

```yaml
volumes:
- name: app-data
  hostPath:
    path: /mnt/primary/k3s-storage/app-name-data
    type: DirectoryOrCreate
```

Mount in containers:
```yaml
volumeMounts:
- name: app-data
  mountPath: /data
```

### Database Dependencies

For apps requiring databases, create separate deployments with services:

1. **Postgres Example** (see `apps/maybe/postgres.yaml`)
2. **Redis Example** (see `apps/maybe/redis.yaml`)

Each database should have:
- Dedicated deployment with resource limits
- Persistent hostPath volume
- Health checks (liveness/readiness probes)
- ClusterIP service for internal access
- Shared secrets with the main application

## Secret Management

Secrets are managed via 1Password CLI integration:

1. **Store secrets in 1Password** with vault `homelab`
2. **Tag secrets** with the target namespace name
3. **Run sync script**: `./scripts/secrets.sh <namespace>`
4. **Automatic sync** - Script compares timestamps and only updates when needed

### Secret Naming Convention
- Secret items in 1Password should match the Kubernetes secret name
- Use descriptive field labels that become environment variable names
- Common secrets:
  - `tailscale-auth` (cluster-wide)
  - `app-name-secrets` (app-specific credentials)

## Deployment Process

### Application Deployment
```bash
# Deploy single app
kubectl apply -k apps/app-name/

# Deploy all apps (via script)
./scripts/deploy.sh
```

### Secret Deployment
```bash
# Sync secrets for specific app
./scripts/secrets.sh app-name
```

## Creating New Applications

### 1. Create App Directory
```bash
mkdir apps/new-app
cd apps/new-app
```

### 2. Create Required Files
Copy and modify files from reference apps (`maybe` or `copyparty`):

1. Start with `kustomization.yaml`
2. Create `namespace.yaml` with your app name
3. Set up `rbac.yaml` (usually identical)
4. Create `secrets.yaml` placeholder
5. Configure `serve-config.yaml` with correct hostname and port
6. Build `deployment.yaml` following the multi-container pattern

### 3. Add Optional Components
- Database deployments if needed
- Additional services (Samba, etc.)
- Application-specific ConfigMaps

### 4. Configure Secrets
1. Add secrets to 1Password vault `homelab`
2. Tag with namespace name
3. Run `./scripts/secrets.sh new-app`

### 5. Deploy
```bash
kubectl apply -k apps/new-app/
```

## Reference Applications

- **`apps/maybe/`** - Full-stack Rails app with Postgres, Redis, and worker containers
- **`apps/copyparty/`** - File server with Samba integration and custom configuration

These serve as the best examples of the established patterns and should be referenced when creating new applications.

## Best Practices

1. **Always use resource limits** - Prevents resource starvation
2. **Include health checks** - Enables proper rolling updates and self-healing
3. **Use init containers** - For dependency waiting and initialization
4. **Follow naming conventions** - Consistent naming across resources
5. **Isolate with namespaces** - Each app gets its own namespace
6. **Secure with Tailscale** - No direct external exposure, always via Tailscale
7. **Document configuration** - Use ConfigMaps for complex app config
8. **Test deployments** - Verify health checks and connectivity after deployment
