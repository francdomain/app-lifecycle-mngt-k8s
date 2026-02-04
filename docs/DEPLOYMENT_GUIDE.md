# E-Commerce Microservices Application - Deployment Guide

## Architecture Overview

### System Components

```
┌─────────────────────────────────────────────────────────┐
│                    External Users                        │
└──────────────┬──────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────┐
│                  LoadBalancer Services                   │
│  (Frontend LB, API Gateway LB)                           │
└──────────────┬──────────────────────────────────────────┘
               │
       ┌───────┴───────┐
       │               │
       ▼               ▼
  ┌─────────┐   ┌──────────────┐
  │Frontend │   │ API Gateway  │
  │ Nginx   │   │  (nginx)     │
  │ Pod     │   │  Pod         │
  └────┬────┘   └──────┬───────┘
       │              │
       │    ┌─────────┴─────────┐
       │    │                   │
       ▼    ▼                   ▼
    ┌────────────┐      ┌────────────────┐
    │ Kubernetes │      │  Kubernetes    │
    │  Namespace │      │   Namespace    │
    │ "ecommerce"│      │  "ecommerce"   │
    └────────────┘      └────────────────┘
         │                       │
         ├─ ConfigMaps           ├─ Product Service
         ├─ Secrets              ├─ Order Service
         ├─ Services             ├─ Health Checks
         └─ Deployments          └─ HPAs
```

### Application Tier Architecture

```
                    PRESENTATION TIER
                    ┌──────────────┐
                    │  Frontend    │
                    │  (nginx)     │
                    │  ✓ Canary    │
                    │  ✓ HPA       │
                    └──────┬───────┘
                           │
                    API TIER
                    ┌──────────────┐
                    │ API Gateway  │
                    │  (nginx)     │
                    │  ✓ Blue/Green│
                    │  ✓ HPA       │
                    └──────┬───────┘
                           │
           ┌───────────────┴───────────────┐
           │                               │
        BACKEND SERVICES
        ┌──────────────┐         ┌──────────────┐
        │   Product    │         │    Order     │
        │   Service    │         │    Service   │
        │  (httpbin)   │         │  (httpbin)   │
        │  ✓ Rolling   │         │  ✓ Rolling   │
        │  ✓ HPA       │         │  ✓ HPA       │
        └──────────────┘         └──────────────┘
```

## Prerequisites

- Kubernetes cluster 1.20+ (tested on 1.24+)
- kubectl CLI tool
- Helm 3.x
- Optional: Flagger + Prometheus (for canary deployments)
- Optional: Argo Rollouts (for advanced deployment strategies)

### Cluster Requirements

- Minimum 3 worker nodes
- Minimum 2GB RAM per node
- Resource requests/limits enabled
- Metrics server installed (for HPA)

## Installation Methods

### Method 1: Deploy Using Kubectl

#### Step 1: Create Namespace and Base Resources

```bash
# Apply namespace
kubectl apply -f manifests/00-namespace.yaml

# Apply ConfigMaps and Secrets
kubectl apply -f manifests/01-configmaps.yaml
kubectl apply -f manifests/02-secrets.yaml

# Apply Services
kubectl apply -f manifests/03-services.yaml

# Apply Deployments
kubectl apply -f manifests/04-deployments.yaml

# Apply HPAs
kubectl apply -f manifests/05-hpa.yaml
```

#### Step 2: Verify Deployment

```bash
# Check namespace
kubectl get namespaces

# Check pods
kubectl get pods -n ecommerce

# Check services
kubectl get svc -n ecommerce

# Check deployments
kubectl get deployments -n ecommerce

# Check HPAs
kubectl get hpa -n ecommerce
```

#### Step 3: Access the Application

```bash
# Get external IP (wait for LoadBalancer assignment)
kubectl get svc -n ecommerce

# Frontend: http://<FRONTEND_EXTERNAL_IP>
# API Gateway: http://<API_GATEWAY_EXTERNAL_IP>
```

### Method 2: Deploy Using Helm

#### Step 1: Install Helm Chart

```bash
# From the helm-chart directory
helm install ecommerce-app ./helm-chart -n ecommerce --create-namespace

# Or with custom values
helm install ecommerce-app ./helm-chart \
  -n ecommerce \
  --create-namespace \
  -f custom-values.yaml
```

#### Step 2: Verify Installation

```bash
# List releases
helm list -n ecommerce

# Check release status
helm status ecommerce-app -n ecommerce

# Get release details
helm get values ecommerce-app -n ecommerce
```

#### Step 3: Upgrade Chart

```bash
# Update values
helm upgrade ecommerce-app ./helm-chart -n ecommerce -f new-values.yaml

# Rollback if needed
helm rollback ecommerce-app 1 -n ecommerce
```

## Deployment Strategies

### 1. Canary Deployment (Frontend)

#### Prerequisites

```bash
# Install Flagger
helm repo add flagger https://flagger.app
helm repo update
helm install flagger flagger/flagger \
  -n flagger-system --create-namespace \
  --set prometheus.install=true
```

#### Deploy Canary Update

```bash
# Apply canary configuration
kubectl apply -f deployment-strategies/01-canary-bluegreen.yaml

# Monitor canary status
kubectl describe canary frontend -n ecommerce

# Watch metrics
kubectl logs -f deployment/flagger-system -n flagger-system
```

#### Canary Strategy

- Initial: 10% traffic to new version
- Stages: 25%, 50%, 75%, 100%
- Validation: 5-minute pause between stages
- Rollback: Automatic on metrics failure

### 2. Blue-Green Deployment (API Gateway)

#### Initial Setup (Blue - Active)

```bash
# Apply blue-green manifests
kubectl apply -f deployment-strategies/01-canary-bluegreen.yaml

# Verify blue deployment
kubectl get pods -n ecommerce -l app=api-gateway,version=v1
```

#### Switch to Green (New Version)

```bash
# Step 1: Scale green deployment
kubectl scale deployment api-gateway-green --replicas=2 -n ecommerce

# Step 2: Wait for ready pods
kubectl wait --for=condition=ready pod \
  -l app=api-gateway,version=v2 \
  -n ecommerce --timeout=300s

# Step 3: Update api-gateway service selector
kubectl patch service api-gateway -n ecommerce -p \
  '{"spec":{"selector":{"version":"v2"}}}'

# Step 4: Scale down blue deployment
kubectl scale deployment api-gateway-blue --replicas=0 -n ecommerce
```

#### Rollback to Blue

```bash
# Update service back to blue
kubectl patch service api-gateway -n ecommerce -p \
  '{"spec":{"selector":{"version":"v1"}}}'

# Scale up blue
kubectl scale deployment api-gateway-blue --replicas=2 -n ecommerce

# Scale down green
kubectl scale deployment api-gateway-green --replicas=0 -n ecommerce
```

### 3. Rolling Updates (Backend Services)

Backend services use standard rolling update strategy:

```bash
# Update image
kubectl set image deployment/product-service \
  product-service=kennethreitz/httpbin:new-tag \
  -n ecommerce

# Monitor rollout
kubectl rollout status deployment/product-service -n ecommerce

# Rollback if needed
kubectl rollout undo deployment/product-service -n ecommerce
```

## Health Checks Configuration

All services implement three types of probes:

### Startup Probe

- Gives container time to start
- Config: 5s initial delay, 5s period
- Failure after 3 consecutive failures

### Readiness Probe

- Determines if container can receive traffic
- Config: 10s initial delay, 10s period
- Failure after 2 consecutive failures

### Liveness Probe

- Detects if container is deadlocked
- Config: 20s initial delay, 15s period
- Failure after 3 consecutive failures

## Autoscaling Configuration

### Frontend HPA

- Target CPU: 70%
- Min replicas: 2
- Max replicas: 10
- Scale up: 100% increase per 30s
- Scale down: 50% decrease per 60s

### API Gateway HPA

- Target CPU: 75%
- Min replicas: 2
- Max replicas: 8
- Supports custom metrics (requests/sec)

### Backend Services HPA

- Target CPU: 80%
- Min replicas: 2
- Max replicas: 6

#### Test Autoscaling

```bash
# Generate load on frontend
kubectl run -i --tty --rm load-generator \
  --image=busybox --restart=Never \
  -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://frontend/; done" \
  -n ecommerce

# Watch HPA scaling
kubectl get hpa -n ecommerce --watch

# Check autoscaling events
kubectl describe hpa frontend-hpa -n ecommerce
```

## Configuration Management

### ConfigMaps

Service URLs, feature flags, and configurations:

```bash
# View ConfigMaps
kubectl get configmaps -n ecommerce

# Edit ConfigMap
kubectl edit configmap service-urls -n ecommerce

# Update and restart pods
kubectl rollout restart deployment/frontend -n ecommerce
```

### Secrets

API keys and sensitive data:

```bash
# View Secrets
kubectl get secrets -n ecommerce

# Create custom secret
kubectl create secret generic my-secret \
  --from-literal=key=value \
  -n ecommerce

# Update secret
kubectl patch secret api-keys -n ecommerce \
  -p '{"data":{"API_KEY":"'$(echo -n 'new-key' | base64)'"}}'
```

## Monitoring and Troubleshooting

### View Logs

```bash
# View pod logs
kubectl logs -f deployment/frontend -n ecommerce

# View previous logs (for crashed pods)
kubectl logs deployment/frontend -n ecommerce --previous

# View logs from all pods in deployment
kubectl logs -f deployment/frontend --all-containers=true -n ecommerce
```

### Debug Pods

```bash
# Get pod details
kubectl describe pod <pod-name> -n ecommerce

# Execute command in pod
kubectl exec -it <pod-name> -n ecommerce -- /bin/sh

# Port forward to pod
kubectl port-forward pod/<pod-name> 8080:80 -n ecommerce
```

### Check Events

```bash
# View namespace events
kubectl get events -n ecommerce

# Watch events in real-time
kubectl get events -n ecommerce --watch
```

### Resource Usage

```bash
# View pod resource usage
kubectl top pods -n ecommerce

# View node resource usage
kubectl top nodes

# View detailed metrics
kubectl get hpa frontend-hpa -n ecommerce --watch
```

## Cleanup

```bash
# Delete entire namespace (deletes all resources)
kubectl delete namespace ecommerce

# Delete specific resources
kubectl delete deployment frontend -n ecommerce
kubectl delete svc frontend -n ecommerce

# Uninstall Helm release
helm uninstall ecommerce-app -n ecommerce
```

## Advanced Topics

### Custom Metrics for HPA

To enable custom metrics-based autoscaling:

1. Install Prometheus Adapter
2. Define custom metrics
3. Update HPA configuration

### Network Policies

Restrict traffic between pods:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: ecommerce
spec:
  podSelector: {}
  policyTypes:
    - Ingress
```

### Pod Disruption Budgets

Ensure availability during disruptions:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: frontend-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: frontend
```

## Troubleshooting Common Issues

### Pods Not Starting

1. Check pod status: `kubectl describe pod <pod-name> -n ecommerce`
2. Check image availability: `kubectl get images`
3. Check resource availability: `kubectl top nodes`

### Service Not Accessible

1. Check service exists: `kubectl get svc -n ecommerce`
2. Check endpoints: `kubectl get endpoints -n ecommerce`
3. Check pod readiness: `kubectl get pods -n ecommerce -o wide`

### HPA Not Scaling

1. Check metrics-server: `kubectl get deployment metrics-server -n kube-system`
2. Check metrics: `kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes`
3. Check HPA events: `kubectl describe hpa <hpa-name> -n ecommerce`

## References

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [Flagger Documentation](https://docs.flagger.app/)
- [Argo Rollouts Documentation](https://argoproj.github.io/argo-rollouts/)
