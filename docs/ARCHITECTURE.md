# E-Commerce Microservices - Architecture Documentation

## System Architecture

### Overview

This is a modern microservices e-commerce platform deployed on Kubernetes with the following key characteristics:

- **Multi-tier Architecture**: Presentation, API, and Backend tiers
- **Container Orchestration**: Kubernetes-native deployment and scaling
- **Advanced Deployment Strategies**: Canary, Blue-Green, and Rolling updates
- **Automatic Scaling**: HPA for all services
- **Configuration as Code**: All infrastructure defined in YAML
- **Health Management**: Comprehensive probes for reliability

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                         External Users                        │
└──────────────────────┬───────────────────────────────────────┘
                       │ HTTP/HTTPS
        ┌──────────────┴──────────────┐
        │                             │
    ┌───▼────────┐          ┌────────▼───┐
    │  Frontend  │          │ API Gateway│
    │  LoadBalancer Service │
    │  Port: 80  │          │ Port: 80   │
    └───┬────────┘          └────────┬───┘
        │                             │
        │       Kubernetes Cluster    │
        │ ┌────────────────────────────────────┐
        │ │   Namespace: ecommerce             │
        │ │ ┌──────────────────────────────┐   │
        │ │ │    Frontend Pods (3)         │   │
        │ │ │  - Nginx Static Content      │   │
        │ │ │  - HPA: 70% CPU target       │   │
        │ │ │  - Canary Deployment         │   │
        │ │ └──────────────────────────────┘   │
        │ │                                    │
        │ │ ┌──────────────────────────────┐   │
        │ │ │  API Gateway Pods (2)        │   │
        │ │ │  - Nginx Reverse Proxy       │   │
        │ │ │  - HPA: 75% CPU target       │   │
        │ │ │  - Blue/Green Deployment     │   │
        │ │ └──────────────────────────────┘   │
        │ │           │                        │
        │ │    ┌──────┴──────┐                 │
        │ │    │             │                 │
        │ │ ┌──▼──────────────▼─┐ ┌──────────┐│
        │ │ │ Product Service   │ │Order Svc ││
        │ │ │ (httpbin)         │ │(httpbin) ││
        │ │ │ HPA: 80% CPU      │ │HPA: 80%  ││
        │ │ │ Rolling Updates   │ │Rolling   ││
        │ │ └───────────────────┘ └──────────┘│
        │ │                                    │
        │ │ ┌──────────────────────────────┐   │
        │ │ │    ConfigMaps & Secrets      │   │
        │ │ │  - service-urls              │   │
        │ │ │  - feature-flags             │   │
        │ │ │  - api-keys                  │   │
        │ │ └──────────────────────────────┘   │
        │ └────────────────────────────────────┘
        │
        └─────────────────────────────────────┘

```

## Component Details

### 1. Frontend Service

**Purpose**: Serve static web content and user interface

**Technology Stack**:

- Nginx Alpine (lightweight)
- Static HTML/CSS/JavaScript
- SPA (Single Page Application) support

**Configuration**:

- Replicas: 3
- Strategy: Canary deployment
- Scaling: 2-10 pods (70% CPU target)
- Health Checks: Startup, Readiness, Liveness

**Endpoints**:

- `/` - Main application
- `/health` - Health check endpoint
- `/api/products` - Proxied to Product Service
- `/api/orders` - Proxied to Order Service

### 2. API Gateway

**Purpose**: Reverse proxy and request routing

**Technology Stack**:

- Nginx Alpine
- Reverse proxy configuration
- Request routing and load balancing

**Configuration**:

- Replicas: 2
- Strategy: Blue-Green deployment
- Scaling: 2-8 pods (75% CPU target)
- Health Checks: All three types

**Responsibilities**:

- Route `/api/products` → Product Service
- Route `/api/orders` → Order Service
- Load balancing
- Request/response modification
- Static file serving

### 3. Product Service

**Purpose**: Product catalog and inventory management

**Technology Stack**:

- httpbin (HTTP request/response service for simulation)
- RESTful API
- JSON responses

**Configuration**:

- Replicas: 2
- Strategy: Rolling update
- Scaling: 2-6 pods (80% CPU target)
- Health Checks: All three types

**Endpoints**:

- `GET /` - Service info
- `GET /status/200` - Health check
- Any httpbin endpoints for API testing

### 4. Order Service

**Purpose**: Order processing and management

**Technology Stack**:

- httpbin (HTTP request/response service for simulation)
- RESTful API
- JSON responses

**Configuration**:

- Replicas: 2
- Strategy: Rolling update
- Scaling: 2-6 pods (80% CPU target)
- Health Checks: All three types

**Endpoints**:

- `GET /` - Service info
- `GET /status/200` - Health check
- Any httpbin endpoints for API testing

## Kubernetes Resources

### Namespace

```yaml
name: ecommerce
labels:
  app: ecommerce-app
```

### Services

| Service         | Type         | Port | Selector             | Purpose                     |
| --------------- | ------------ | ---- | -------------------- | --------------------------- |
| frontend        | LoadBalancer | 80   | app: frontend        | External access to frontend |
| api-gateway     | LoadBalancer | 80   | app: api-gateway     | External access to API      |
| product-service | ClusterIP    | 8080 | app: product-service | Internal service discovery  |
| order-service   | ClusterIP    | 8080 | app: order-service   | Internal service discovery  |

### ConfigMaps

| Name               | Purpose                | Keys                                         |
| ------------------ | ---------------------- | -------------------------------------------- |
| service-urls       | Service discovery URLs | PRODUCT_SERVICE_URL, ORDER_SERVICE_URL, etc. |
| feature-flags      | Feature toggles        | FEATURE_NEW_DASHBOARD, CACHE_ENABLED, etc.   |
| api-gateway-config | Nginx configuration    | nginx.conf                                   |
| frontend-html      | HTML content           | index.html                                   |

### Secrets

| Name     | Type   | Keys                             | Usage                            |
| -------- | ------ | -------------------------------- | -------------------------------- |
| api-keys | Opaque | API_KEY, DB_PASSWORD, JWT_SECRET | Authentication and authorization |

## Deployment Strategies

### Frontend: Canary Deployment

Progressive rollout with traffic shifting and automated rollback:

```
Stage 1: 10% traffic
├─ Monitor metrics for 5 minutes
├─ Success? Continue
└─ Failure? Automatic rollback

Stage 2: 25% traffic
├─ Monitor metrics for 5 minutes
└─ ...

Stage 3: 50% traffic
├─ Monitor metrics for 5 minutes
└─ ...

Stage 4: 100% traffic
└─ Complete deployment
```

**Benefits**:

- Low-risk updates
- Real traffic testing
- Automatic rollback on failure
- Minimal downtime

### API Gateway: Blue-Green Deployment

Two identical production environments:

```
Current (Blue) - Active
├─ Version: v1
├─ Replicas: 2
└─ All traffic routed here

Next (Green) - Standby
├─ Version: v2
├─ Replicas: 0 (scaled up before switch)
└─ No traffic initially

Deployment Process:
1. Scale up Green
2. Verify all Green pods are ready
3. Switch traffic from Blue to Green
4. Keep Blue available for quick rollback
5. Scale down Blue after stability
```

**Benefits**:

- Instant rollback capability
- Zero-downtime deployments
- Testing in production environment
- Complete resource isolation

### Backend Services: Rolling Updates

Gradual replacement of pods:

```
Current: 2 replicas of v1
Target: 2 replicas of v2

Update Steps:
1. Spin up 1 pod v2 (total: 3)
2. Remove 1 pod v1 (total: 2 new + 1 old)
3. Spin up 1 pod v2 (total: 2 new + 1 old)
4. Remove 1 pod v1 (total: 2 new)
```

**Benefits**:

- Simple and reliable
- Automatic rollback support
- Resource-efficient
- Pod disruption budget support

## Health Check Strategy

### Startup Probe

- **Purpose**: Detect if container is starting up
- **Configuration**:
  - Initial delay: 5 seconds
  - Period: 5 seconds
  - Timeout: 2 seconds
  - Failure threshold: 3 attempts
- **Path**: `/health` or `/status/200`

### Readiness Probe

- **Purpose**: Determine if pod can receive traffic
- **Configuration**:
  - Initial delay: 10 seconds
  - Period: 10 seconds
  - Timeout: 3 seconds
  - Failure threshold: 2 attempts
- **Path**: `/health` or `/status/200`

### Liveness Probe

- **Purpose**: Detect if pod is deadlocked
- **Configuration**:
  - Initial delay: 20 seconds
  - Period: 15 seconds
  - Timeout: 3 seconds
  - Failure threshold: 3 attempts
- **Path**: `/health` or `/status/200`

## Autoscaling Strategy

### Horizontal Pod Autoscaler (HPA)

All services implement HPA v2 for advanced metrics:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: <service>-hpa
spec:
  scaleTargetRef:
    kind: Deployment
    name: <service>
  minReplicas: <min>
  maxReplicas: <max>
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          averageUtilization: <target>%
```

### Frontend Scaling Behavior

```
Scale Up (Aggressive):
├─ Trigger: CPU > 70%
├─ Action: Increase 100% per 30 seconds
├─ Max addition: 2 pods per 30 seconds
└─ Target range: 2-10 pods

Scale Down (Conservative):
├─ Trigger: CPU < 70% for 5 minutes
├─ Action: Decrease 50% per 60 seconds
├─ Max removal: 1 pod per 60 seconds
└─ Target range: 2-10 pods
```

### API Gateway Scaling

```
Primary Metric: CPU (75% target)
Fallback Metrics: Custom metrics (requests/second)
Min/Max: 2-8 pods
```

## Configuration Management

### Environment Variables

Injected from ConfigMaps and Secrets:

```yaml
env:
  - name: PRODUCT_SERVICE_URL
    valueFrom:
      configMapKeyRef:
        name: service-urls
        key: PRODUCT_SERVICE_URL

  - name: API_KEY
    valueFrom:
      secretKeyRef:
        name: api-keys
        key: API_KEY
```

### Service Discovery

Kubernetes DNS provides automatic service discovery:

```
<service-name>.<namespace>.svc.cluster.local
product-service.ecommerce.svc.cluster.local
order-service.ecommerce.svc.cluster.local
```

## Resource Management

### Resource Requests and Limits

Ensure fair resource distribution:

```yaml
Frontend:
  requests: 100m CPU, 128Mi memory
  limits: 500m CPU, 256Mi memory

API Gateway:
  requests: 100m CPU, 128Mi memory
  limits: 500m CPU, 256Mi memory

Backend Services:
  requests: 50m CPU, 64Mi memory
  limits: 250m CPU, 128Mi memory
```

### Quality of Service (QoS)

All pods are "Burstable" class:

- Requests defined
- Limits higher than requests
- Can be evicted if necessary
- Lower priority than "Guaranteed" pods

## Security Considerations

### Secret Management

- API keys stored as Kubernetes Secrets
- Base64 encoded (not encrypted by default)
- Recommendation: Enable encryption at rest
- Consider using external secret management (HashiCorp Vault, etc.)

### Network Access

- Services use ClusterIP for internal communication
- LoadBalancer only for public-facing services
- Consider Network Policies for additional isolation

### RBAC (Role-Based Access Control)

```yaml
# Example: Limit deployment update access
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deployment-updater
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "patch"]
```

## Monitoring and Observability

### Metrics to Track

1. **Pod Metrics**:
   - CPU usage
   - Memory usage
   - Network I/O

2. **Application Metrics**:
   - Request rate
   - Error rate
   - Response latency

3. **Deployment Metrics**:
   - Replica count
   - Pod ready status
   - Update progress

4. **HPA Metrics**:
   - Target utilization
   - Current utilization
   - Desired replicas

### Recommended Tools

- **Prometheus**: Metrics collection and alerting
- **Grafana**: Metrics visualization
- **Flagger**: Canary deployment automation
- **Datadog/New Relic**: APM and monitoring

## High Availability (HA)

### Design Principles

1. **Multi-replica deployments**: 2+ pods per service
2. **Pod Disruption Budgets**: Minimum pod availability during disruptions
3. **Health checks**: Quick detection and recovery
4. **Auto-scaling**: Handle load spikes
5. **Rolling updates**: Zero-downtime deployments

### Recovery Strategies

1. **Pod failure**: Kubelet restarts pod
2. **Node failure**: Pods rescheduled to healthy nodes
3. **Deployment failure**: Rollback to previous version
4. **Canary issues**: Automatic rollback
5. **Blue-Green issues**: Quick switch back to blue

## Disaster Recovery

### Backup Strategy

```bash
# Backup manifests
git commit -am "Pre-deployment backup"

# Backup configuration
kubectl get all -n ecommerce -o yaml > backup.yaml
```

### Recovery Procedures

```bash
# Full namespace restore
kubectl apply -f backup.yaml

# Selective resource restore
kubectl apply -f manifests/04-deployments.yaml
```

## Cost Optimization

### Resource Optimization

- Right-size resource requests
- Use node affinity for efficient scheduling
- Enable cluster autoscaling
- Use spot instances for non-critical workloads

### Metrics

With current settings:

- **Frontend**: 3 pods × (100m CPU, 128Mi mem) = 300m CPU, 384Mi mem
- **API Gateway**: 2 pods × (100m CPU, 128Mi mem) = 200m CPU, 256Mi mem
- **Backend**: 4 pods × (50m CPU, 64Mi mem) = 200m CPU, 256Mi mem

**Total baseline**: 700m CPU, 896Mi memory

With HPA expansion to max:

- **Total max**: 2.1 CPU, 2.6GB memory

## References and Further Reading

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [Kubernetes Patterns](https://www.oreilly.com/library/view/kubernetes-patterns/9781617293726/)
- [Cloud Native DevOps](https://www.oreilly.com/library/view/cloud-native-devops/9781492040292/)
