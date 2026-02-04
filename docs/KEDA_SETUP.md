# KEDA (Kubernetes Event-Driven Autoscaling) Implementation

## Overview

This project has been enhanced with KEDA (Kubernetes Event-Driven Autoscaling) for advanced, event-driven autoscaling capabilities beyond traditional CPU/memory-based metrics.

**Traditional HPA vs KEDA**:
| Feature | HPA | KEDA |
|---------|-----|------|
| CPU/Memory Metrics | ✅ | ✅ |
| Custom Metrics | ⚠️ Limited | ✅ Full Support |
| Event-Driven Scaling | ❌ | ✅ |
| Queue-Based Scaling | ❌ | ✅ |
| Multiple Triggers | ❌ | ✅ |
| Graceful Fallbacks | ❌ | ✅ |
| Metric Adapters | Requires Setup | Built-in |

## Architecture

### KEDA Components

```
┌─────────────────────────────────────────────────────┐
│           Kubernetes Cluster                        │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │          KEDA Namespace                      │  │
│  ├──────────────────────────────────────────────┤  │
│  │                                              │  │
│  │  ┌──────────────────┐  ┌─────────────────┐  │  │
│  │  │ KEDA Operator    │  │ Metrics Server  │  │  │
│  │  │ (watches events) │  │ (processes data)│  │  │
│  │  └──────────────────┘  └─────────────────┘  │  │
│  │                                              │  │
│  └──────────────────────────────────────────────┘  │
│                         ↑                          │
│                         │ (triggers)               │
│                         │                          │
│  ┌──────────────────────────────────────────────┐  │
│  │        ecommerce Namespace                   │  │
│  ├──────────────────────────────────────────────┤  │
│  │                                              │  │
│  │  ┌──────────────┐  ┌────────────────────┐   │  │
│  │  │ ScaledObjects│─→│ Generated HPA      │   │  │
│  │  │ (config)     │  │ (auto-created)     │   │  │
│  │  └──────────────┘  └────────────────────┘   │  │
│  │         │                  │                │  │
│  │         └──────────┬───────┘                │  │
│  │                    ↓                        │  │
│  │         ┌──────────────────────┐           │  │
│  │         │ Scaled Deployments   │           │  │
│  │         │ - Frontend           │           │  │
│  │         │ - API Gateway        │           │  │
│  │         │ - Product Service    │           │  │
│  │         │ - Order Service      │           │  │
│  │         └──────────────────────┘           │  │
│  │                                              │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │ External Metric Sources                      │  │
│  ├──────────────────────────────────────────────┤  │
│  │ • Prometheus (HTTP requests, latency, etc)   │  │
│  │ • Message Queues (RabbitMQ, Kafka, etc)      │  │
│  │ • Cloud Services (AWS SQS, Azure Queues)     │  │
│  │ • Custom Webhooks                            │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## Deployment

### Installation

```bash
# Deploy KEDA operator and ScaledObjects
./scripts/deploy-keda.sh ecommerce

# Or deploy with kubectl directly
kubectl apply -f manifests/06-keda-setup.yaml  # KEDA operator
kubectl apply -f manifests/07-keda-scalers.yaml  # ScaledObjects
```

### Prerequisites

1. **Kubernetes 1.18+** - KEDA requires a modern Kubernetes version
2. **Metrics Server** - For CPU/memory triggers (usually pre-installed)
3. **Prometheus** (Optional) - For custom metrics
   ```bash
   # If using Prometheus-based triggers, ensure it's accessible at:
   # http://prometheus:9090 (default, update in ScaledObjects if needed)
   ```

### Files Structure

```
manifests/
├── 06-keda-setup.yaml      # KEDA operator, RBAC, and metrics server
└── 07-keda-scalers.yaml    # ScaledObject configurations for all services

scripts/
└── deploy-keda.sh          # Deployment automation script
```

## ScaledObject Configurations

### 1. Frontend Scaler

**Scaling Triggers**:

```
Primary:   HTTP request rate (Prometheus)
Fallback:  CPU utilization (70%) + Memory (80%)
Range:     2-10 replicas
```

**Behavior**:

- Scale up: 100% increase every 30 seconds
- Scale down: 50% decrease every 60 seconds

**Metrics**:

- HTTP request rate: `sum(rate(nginx_http_requests_total{job="frontend"}[30s]))`
- Threshold: >100 requests/sec triggers scale up

```yaml
triggers:
  - type: prometheus
    threshold: "100" # requests/sec
```

### 2. API Gateway Scaler

**Scaling Triggers**:

```
Primary:   HTTP request rate (Prometheus)
Secondary: Request latency (95th percentile) via Prometheus
Fallback:  CPU utilization (75%)
Range:     2-8 replicas
```

**Behavior**:

- Scale up aggressively: 100% increase every 30 seconds
- Scale down gradually: 50% decrease every 60 seconds

**Metrics**:

- Request rate: `sum(rate(nginx_http_requests_total{job="api-gateway"}[30s]))`
- Latency: `histogram_quantile(0.95, nginx_http_request_duration_seconds_bucket)`
- Thresholds: 500 req/sec or 1000ms latency

### 3. Product Service Scaler

**Scaling Triggers**:

```
Primary:   Database query latency (95th percentile)
Secondary: HTTP request rate
Fallback:  CPU utilization (80%) + Memory (75%)
Range:     2-6 replicas
```

**Behavior**:

- Scale up moderately: 50% increase every 60 seconds
- Scale down conservatively: 25% decrease every 120 seconds

**Metrics**:

- DB latency: `histogram_quantile(0.95, db_query_duration_seconds_bucket)`
- Threshold: >500ms triggers scale up

### 4. Order Service Scaler

**Scaling Triggers**:

```
Primary:   Order queue depth (pending orders)
Secondary: POST request rate
Tertiary:  Order processing time (99th percentile)
Fallback:  CPU utilization (80%)
Range:     2-6 replicas
```

**Behavior**:

- Scale up aggressively: 100% increase every 30 seconds
- Scale down gradually: 50% decrease every 60 seconds

**Metrics**:

- Queue depth: `sum(increase(orders_pending_total[5m]))`
- Processing time: `histogram_quantile(0.99, order_processing_duration_seconds_bucket)`

## How It Works

### ScaledObject Processing Flow

```
1. ScaledObject Definition Created
   └─> KEDA operator reads configuration

2. Triggers Evaluated (periodically, default 30s)
   ├─> Prometheus query executed
   ├─> Metric value compared to threshold
   └─> Evaluation result cached

3. Desired Replica Count Calculated
   ├─> All triggers evaluated (AND logic for multiple triggers)
   ├─> Highest required replica count selected
   ├─> Scaling behaviors applied
   └─> Fallback activated if metric unavailable

4. HPA Generated/Updated
   └─> KEDA creates/updates HPA resource automatically

5. Kubernetes Scaling Executed
   ├─> Deployment replica count adjusted
   ├─> Pod creation/termination
   └─> Health checks and readiness gates applied
```

### Example: Frontend Scaling Scenario

**Scenario: Traffic spike detected**

```
Time: 10:00:00
- HTTP request rate: 95 req/sec (below 100 threshold)
- Replicas: 2 (minimum)

Time: 10:00:30
- HTTP request rate: 250 req/sec (above 100 threshold)
- Calculation: ceil(250 / 100) = 3 replicas needed
- Action: Scale up to 3 replicas
- HPA updated with new minReplicas: 3

Time: 10:01:00
- HTTP request rate: 500 req/sec (still high)
- Current: 3 replicas, each handling ~167 req/sec
- Calculation: ceil(500 / 100) = 5 replicas needed
- Action: Scale up to 5 replicas (100% increase allowed)
- HPA updated: minReplicas: 5

Time: 10:05:00
- HTTP request rate: 150 req/sec (returning to normal)
- Stabilization window: 300s (5 minutes)
- Action: No scale down (still within stabilization window)

Time: 10:10:00
- HTTP request rate: 100 req/sec (stable, low)
- Stabilization window: Expired
- Calculation: ceil(100 / 100) = 1 (minimum is 2, so scale to 2)
- Action: Scale down to 2 replicas (50% decrease)
```

## Comparison with Original HPA

### HPA Configuration (Original)

```yaml
# manifests/05-hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: frontend-hpa
  namespace: ecommerce
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: frontend
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70 # Only CPU-based
```

**Limitations**:

- Only CPU/memory metrics
- No queue or request-based scaling
- No fallback mechanism
- Requires separate metrics server setup

### KEDA ScaledObject (New)

```yaml
# manifests/07-keda-scalers.yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: frontend-scaler
  namespace: ecommerce
spec:
  scaleTargetRef:
    name: frontend
  minReplicaCount: 2
  maxReplicaCount: 10
  triggers:
    - type: prometheus
      metadata:
        query: sum(rate(nginx_http_requests_total{job="frontend"}[30s]))
        threshold: "100"
    - type: cpu
      metadata:
        value: "70"
  fallbacks:
    - failureType: all
      replicas: 3 # Fallback if metrics unavailable
```

**Advantages**:

- Multiple event sources
- Custom metric support
- Graceful fallbacks
- Built-in metrics server
- Better observability

## Monitoring and Troubleshooting

### View KEDA Status

```bash
# Check KEDA operator pods
kubectl get pods -n keda

# View KEDA operator logs
kubectl logs -n keda -l app=keda -f

# Check metrics server
kubectl get deployment keda-metrics-apiserver -n keda

# Verify ScaledObjects
kubectl get scaledobjects -n ecommerce
kubectl describe scaledobject frontend-scaler -n ecommerce

# View generated HPA
kubectl get hpa -n ecommerce
kubectl describe hpa keda-frontend-scaler -n ecommerce

# Monitor scaling events
kubectl get events -n ecommerce --sort-by='.lastTimestamp' | tail -20
```

### Common Issues

**Issue: ScaledObject not scaling**

```bash
# Check ScaledObject status
kubectl describe scaledobject frontend-scaler -n ecommerce

# View conditions and error messages
kubectl get scaledobjects -n ecommerce -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Paused")]}{"\n"}{end}'
```

**Issue: Prometheus metrics not found**

```bash
# Verify Prometheus connectivity
kubectl run prometheus-test --image=curlimages/curl -it --rm --restart=Never -- \
  curl http://prometheus:9090/api/v1/query?query=up

# Check metric names in Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Then visit http://localhost:9090 in browser and check metrics
```

**Issue: Scaling not happening as expected**

```bash
# Check HPA details
kubectl get hpa -n ecommerce -o yaml

# View current metric values
kubectl top pod -n ecommerce
kubectl get hpa -n ecommerce --watch

# Check autoscaler controller logs
kubectl logs -n keba -l app=keda --all-containers=true
```

## Integration with Deployment Pipeline

### Deployment with KEDA

Update `deploy.sh` to optionally deploy KEDA:

```bash
# Deploy application with KEDA
./scripts/deploy.sh ecommerce kubectl
./scripts/deploy-keda.sh ecommerce

# Or deploy with Helm (you can add KEDA to Helm chart)
./scripts/deploy.sh ecommerce helm
./scripts/deploy-keda.sh ecommerce
```

### Using with Helm

The KEDA setup can be integrated into your Helm chart:

```bash
# Add KEDA Helm repository
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# Install KEDA via Helm (alternative to YAML manifests)
helm install keda kedacore/keda --namespace keda --create-namespace

# Your application deployment with ScaledObjects
helm install myapp ./helm-chart -n ecommerce
```

## Best Practices

### 1. Metric Selection

- Choose metrics that correlate with actual load
- Use percentile-based metrics (p95, p99) for latency
- Combine multiple triggers for better accuracy

### 2. Threshold Tuning

- Start with conservative thresholds
- Test scaling behavior under realistic load
- Adjust based on actual performance metrics

### 3. Fallback Strategy

- Always configure CPU/memory fallbacks
- Set appropriate fallback replica counts
- Test fallback behavior when metrics are unavailable

### 4. Monitoring

- Set up dashboards to visualize scaling events
- Alert on scaling anomalies
- Monitor KEDA operator health

### 5. Cost Optimization

- Set appropriate maxReplicaCount to control costs
- Use longer stabilization windows for workloads
- Combine queue and request-rate triggers

### 6. Security

- Use TriggerAuthentication for secure credential passing
- Restrict RBAC permissions for KEDA operator
- Enable pod security policies

## Migration from HPA to KEDA

### Step-by-Step Migration

1. **Keep HPA during transition**

   ```bash
   # Both HPA and ScaledObject can coexist
   kubectl apply -f manifests/05-hpa.yaml    # Existing HPA
   kubectl apply -f manifests/07-keda-scalers.yaml  # New ScaledObject
   ```

2. **Monitor both scaling systems**

   ```bash
   kubectl get hpa,scaledobjects -n ecommerce -w
   ```

3. **Test KEDA scaling**
   - Generate load and verify KEDA scaling
   - Compare behavior with HPA
   - Ensure metrics are accurate

4. **Remove HPA** (when confident in KEDA)
   ```bash
   kubectl delete hpa -n ecommerce -l old=true
   ```

### Rollback Plan

If issues occur with KEDA:

```bash
# Delete ScaledObjects (HPA still works)
kubectl delete scaledobjects -n ecommerce --all

# Or temporarily pause KEDA
kubectl patch scaledobject frontend-scaler -p '{"spec":{"paused":true}}'

# HPA will still manage scaling
kubectl get hpa -n ecommerce
```

## Advanced Configuration

### Custom Metrics

```yaml
# Add custom metric for business logic
- type: prometheus
  metadata:
    serverAddress: http://prometheus:9090
    metricName: custom_business_metric
    threshold: "1000"
    query: |
      custom_metric{service="order-service"}
```

### Authentication to Metric Sources

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: prometheus-auth
  namespace: ecommerce
spec:
  secretTargetRef:
    - parameter: bearerToken
      name: prometheus-secret
      key: token

---
# Use in ScaledObject
triggers:
  - type: prometheus
    metadata:
      serverAddress: https://prometheus.example.com
      metricName: http_requests
    authModes: ["bearer"]
    auth:
      name: prometheus-auth
```

### Multiple Metrics (AND Logic)

When multiple triggers are defined, KEDA scales based on the **maximum required replicas**:

```
If Trigger 1 needs 5 replicas
And Trigger 2 needs 8 replicas
KEDA will scale to 8 replicas (the maximum)
```

## References

- [KEDA Official Documentation](https://keda.sh)
- [Prometheus Query Examples](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [ScaledObject API](https://keda.sh/docs/latest/concepts/scaling-deployments/)
- [Available KEDA Scalers](https://keda.sh/docs/latest/scalers/)

## Summary

KEDA provides:
✅ Event-driven autoscaling
✅ Multiple trigger support
✅ Custom metrics integration
✅ Graceful fallback mechanisms
✅ Better observability and control
✅ Production-ready scaling policies

The migration from HPA to KEDA maintains full backward compatibility while enabling advanced scaling scenarios based on business metrics and event sources.
