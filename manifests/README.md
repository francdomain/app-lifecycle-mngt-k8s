# Configuration Files

This directory contains separated configuration files for easy management and editing.

## Structure

```
manifests/
├── api-gateway/
│   └── nginx.conf          # API Gateway reverse proxy configuration
├── frontend/
│   └── index.html          # Frontend static content
├── 00-namespace.yaml       # Kubernetes namespace
├── 01-configmaps.yaml      # ConfigMaps (references the files above)
├── 02-secrets.yaml         # Secrets (API keys, etc)
├── 03-services.yaml        # Kubernetes services
├── 04-deployments.yaml     # Deployments with health checks
└── 05-hpa.yaml             # Horizontal Pod Autoscaling
```

## Configuration Files Details

### API Gateway Configuration

- **File**: `api-gateway/nginx.conf`
- **Purpose**: Nginx reverse proxy configuration
- **Usage**: Automatically loaded into `api-gateway-config` ConfigMap
- **Routes**:
  - `/api/products` → Product Service (port 8080)
  - `/api/orders` → Order Service (port 8080)
  - `/health` → Health check endpoint

### Frontend Content

- **File**: `frontend/index.html`
- **Purpose**: Static HTML content served by Nginx
- **Usage**: Automatically loaded into `frontend-html` ConfigMap
- **Features**:
  - Responsive design
  - API interaction buttons
  - Real-time health status

## Creating ConfigMaps

### Method 1: Using the Helper Script (Recommended)

```bash
./scripts/create-configmaps.sh ecommerce
```

This script:

- Creates the namespace
- Generates ConfigMaps from the files
- Verifies the ConfigMaps are created

### Method 2: Manual kubectl Commands

```bash
# Create API Gateway ConfigMap
kubectl create configmap api-gateway-config \
  --from-file=api-gateway/nginx.conf \
  -n ecommerce

# Create Frontend ConfigMap
kubectl create configmap frontend-html \
  --from-file=frontend/index.html \
  -n ecommerce
```

### Method 3: From Kubernetes Manifest

```bash
kubectl apply -f 01-configmaps.yaml
```

Note: This applies only the service-urls and feature-flags ConfigMaps. For the large configuration files (nginx.conf, index.html), use Method 1 or 2.

## Updating Configurations

### Update API Gateway Configuration

1. Edit `api-gateway/nginx.conf`
2. Recreate the ConfigMap:
   ```bash
   kubectl create configmap api-gateway-config \
     --from-file=api-gateway/nginx.conf \
     -n ecommerce \
     --dry-run=client -o yaml | kubectl apply -f -
   ```
3. Restart the API Gateway pods:
   ```bash
   kubectl rollout restart deployment/api-gateway -n ecommerce
   ```

### Update Frontend Content

1. Edit `frontend/index.html`
2. Recreate the ConfigMap:
   ```bash
   kubectl create configmap frontend-html \
     --from-file=frontend/index.html \
     -n ecommerce \
     --dry-run=client -o yaml | kubectl apply -f -
   ```
3. Restart the Frontend pods:
   ```bash
   kubectl rollout restart deployment/frontend -n ecommerce
   ```

## Verification

### View ConfigMap Contents

```bash
# API Gateway configuration
kubectl get configmap api-gateway-config -n ecommerce -o jsonpath='{.data}' | jq .

# Frontend HTML
kubectl get configmap frontend-html -n ecommerce -o jsonpath='{.data.index\.html}' | head -20

# Service URLs
kubectl get configmap service-urls -n ecommerce -o jsonpath='{.data}' | jq .

# Feature Flags
kubectl get configmap feature-flags -n ecommerce -o jsonpath='{.data}' | jq .
```

### Mount Points in Pods

The configurations are mounted in the pods as follows:

**Frontend Pod**:

- `frontend-html` mounted at `/usr/share/nginx/html`
- `api-gateway-config` mounted at `/etc/nginx/nginx.conf` (subPath: nginx.conf)

**API Gateway Pod**:

- `api-gateway-config` mounted at `/etc/nginx/nginx.conf` (subPath: nginx.conf)

## Best Practices

1. **Keep files separate**: Easier to manage and edit
2. **Version control**: Track changes in git
3. **Documentation**: Update this file when adding new configurations
4. **Validation**: Always validate syntax before applying:
   - Nginx: `nginx -t -c /path/to/nginx.conf`
   - HTML: Use a validator
5. **Testing**: Test changes in a dev environment first
6. **Rollback plan**: Keep previous ConfigMap versions or backups

## References

- [Kubernetes ConfigMaps Documentation](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Nginx Documentation](https://nginx.org/en/docs/)
- [HTML Specifications](https://html.spec.whatwg.org/)
