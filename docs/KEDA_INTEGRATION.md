# KEDA Integration Guide

## Overview

This guide explains how to integrate KEDA (Kubernetes Event-Driven Autoscaling) into your Kubernetes deployment for advanced, event-driven autoscaling capabilities.

## Quick Start

### 1. Deploy KEDA

```bash
# Single command to install KEDA and configure ScaledObjects
./scripts/deploy-keda.sh ecommerce

# Or manually apply manifests
kubectl apply -f manifests/06-keda-setup.yaml
kubectl apply -f manifests/07-keda-scalers.yaml
```

### 2. Verify Installation

```bash
# Check KEDA operator
kubectl get pods -n keda

# View ScaledObjects
kubectl get scaledobjects -n ecommerce

# Monitor scaling
kubectl get hpa -n ecommerce --watch
```

### 3. Test Scaling

```bash
# Run KEDA test suite
./tests/test-keda.sh ecommerce

# Generate load to trigger scaling
kubectl run -n ecommerce load-test --image=busybox -it --rm -- \
  /bin/sh -c "while true; do wget -q -O- http://frontend; done"

# Watch pods scaling
kubectl get pods -n ecommerce -w
```

## Architecture Changes

### Before (HPA Only)

```
Deployment (frontend)
    ↓
HPA (monitors CPU only)
    ↓
Scales based on CPU utilization: 70%
```

### After (KEDA + HPA)

```
Deployment (frontend)
    ↓
ScaledObject (frontend-scaler)
    ├─ Trigger 1: HTTP Request Rate (Prometheus)
    ├─ Trigger 2: CPU Utilization (fallback)
    └─ Trigger 3: Memory Utilization (fallback)
    ↓
Generated HPA (auto-created by KEDA)
    ↓
Scales based on event-driven metrics
```

## Scalers Breakdown

### 1. Frontend Service

**Metrics**:

- Primary: HTTP request rate (>100 req/sec)
- Fallback: CPU (70%) and Memory (80%)

**Behavior**:

- Min replicas: 2
- Max replicas: 10
- Scale up: 100% per 30s
- Scale down: 50% per 60s

**Use Case**: High-traffic frontend with variable request patterns

### 2. API Gateway

**Metrics**:

- Primary: HTTP request rate (>500 req/sec)
- Secondary: Request latency (>1000ms p95)
- Fallback: CPU (75%)

**Behavior**:

- Min replicas: 2
- Max replicas: 8
- Aggressive scale up: 100% per 30s
- Conservative scale down: 50% per 60s

**Use Case**: Gateway managing traffic spikes with latency concerns

### 3. Product Service

**Metrics**:

- Primary: DB query latency (>500ms p95)
- Secondary: HTTP request rate (>200 req/sec)
- Fallback: CPU (80%) and Memory (75%)

**Behavior**:

- Min replicas: 2
- Max replicas: 6
- Moderate scale up: 50% per 60s
- Conservative scale down: 25% per 120s

**Use Case**: Service with heavy database operations

### 4. Order Service

**Metrics**:

- Primary: Order queue depth (>50 pending)
- Secondary: POST request rate (>150 req/sec)
- Tertiary: Processing time (>2000ms p99)
- Fallback: CPU (80%)

**Behavior**:

- Min replicas: 2
- Max replicas: 6
- Aggressive scale up: 100% per 30s
- Conservative scale down: 50% per 60s

**Use Case**: Event-driven service handling asynchronous orders

## Metrics Configuration

### Prometheus Integration

All scalers use Prometheus for custom metrics. Update the `serverAddress` if your Prometheus is external:

```yaml
# In manifests/07-keda-scalers.yaml
triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus:9090 # Update this if needed
      metricName: http_request_rate
      threshold: "100"
      query: |
        sum(rate(nginx_http_requests_total{job="frontend"}[30s]))
```

### Custom Metrics

To add custom business metrics:

1. **Ensure metrics are exported to Prometheus**:

   ```python
   from prometheus_client import Counter, Histogram

   request_counter = Counter('custom_requests_total', 'Total requests')
   processing_time = Histogram('custom_processing_seconds', 'Processing time')
   ```

2. **Update ScaledObject trigger**:

   ```yaml
   triggers:
     - type: prometheus
       metadata:
         serverAddress: http://prometheus:9090
         metricName: custom_metric
         threshold: "500"
         query: |
           custom_metric{service="my-service"}
   ```

3. **Apply changes**:
   ```bash
   kubectl apply -f manifests/07-keda-scalers.yaml
   ```

## Comparison: HPA vs KEDA

| Feature                | HPA                     | KEDA                        |
| ---------------------- | ----------------------- | --------------------------- |
| **CPU/Memory Metrics** | ✅ Built-in             | ✅ Via CPU/Memory scaler    |
| **Custom Metrics**     | ⚠️ Requires adapter     | ✅ Native support           |
| **Event Sources**      | ❌ Not supported        | ✅ 50+ scalers              |
| **Queue Scaling**      | ❌                      | ✅ (RabbitMQ, SQS, etc.)    |
| **Fallback Replicas**  | ❌                      | ✅ (pausing support)        |
| **Multiple Triggers**  | ❌ (separate resources) | ✅ (in single ScaledObject) |
| **Metric Aggregation** | Basic                   | Advanced                    |
| **Setup Complexity**   | Simple                  | Moderate                    |

## Deployment Strategies

### Strategy 1: Parallel Testing (Recommended)

Run HPA and KEDA together to compare behavior:

```bash
# Deploy application with both HPA and KEDA
kubectl apply -f manifests/05-hpa.yaml       # Original HPA
kubectl apply -f manifests/07-keda-scalers.yaml  # New KEDA

# Monitor both
kubectl get hpa,scaledobjects -n ecommerce -w

# Compare scaling decisions
kubectl get hpa -n ecommerce -o yaml | grep -A 5 "currentReplicas"
kubectl get scaledobjects -n ecommerce -o yaml | grep -A 5 "desiredReplicas"
```

### Strategy 2: Gradual Migration

1. Deploy KEDA with conservative thresholds
2. Monitor for 1-2 days
3. Fine-tune triggers and thresholds
4. Disable HPA for each service
5. Fully remove HPA after validation

### Strategy 3: Full Replacement

Remove HPA and deploy KEDA directly:

```bash
# Remove old HPA
kubectl delete hpa -n ecommerce -l app=ecommerce

# Deploy KEDA
kubectl apply -f manifests/06-keda-setup.yaml
kubectl apply -f manifests/07-keda-scalers.yaml
```

## Troubleshooting

### KEDA Operator Issues

**Problem**: ScaledObject not creating HPA

```bash
# Check KEDA operator logs
kubectl logs -n keda -l app=keda --tail=100

# Check ScaledObject status
kubectl describe scaledobject frontend-scaler -n ecommerce

# View detailed conditions
kubectl get scaledobjects -n ecommerce -o jsonpath='{.items[0].status.conditions[*]}' | jq .
```

**Solution**:

1. Ensure KEDA operator is running: `kubectl get pods -n keda`
2. Check RBAC permissions: `kubectl describe clusterrole keda-operator`
3. Verify ScaledObject YAML syntax

### Prometheus Connection Issues

**Problem**: Metric queries failing

```bash
# Test Prometheus connectivity
kubectl run prometheus-test --image=curlimages/curl -it --rm --restart=Never -- \
  curl -v http://prometheus:9090/api/v1/query?query=up

# Check metric availability
kubectl run prometheus-test --image=curlimages/curl -it --rm --restart=Never -- \
  curl http://prometheus:9090/api/v1/query?query=nginx_http_requests_total
```

**Solution**:

1. Verify Prometheus URL in ScaledObject: `http://prometheus:9090`
2. Check if metrics exist: `kubectl port-forward svc/prometheus 9090:9090`
3. Visit http://localhost:9090 in browser

### Scaling Not Triggering

**Problem**: Metrics are available but scaling not happening

```bash
# Check current metric value
kubectl get scaledobject frontend-scaler -n ecommerce -o yaml | grep -A 10 "status:"

# View metric queries
kubectl describe scaledobject frontend-scaler -n ecommerce | grep -A 5 "Metrics:"

# Check generated HPA
kubectl get hpa keda-frontend-scaler -n ecommerce -o yaml
```

**Solution**:

1. Verify threshold values match metric output
2. Check if metrics are above/below threshold
3. Ensure HPA has correct scaleTargetRef
4. View recent scaling events: `kubectl get events -n ecommerce --sort-by='.lastTimestamp'`

## Monitoring KEDA

### Real-time Monitoring

```bash
# Watch ScaledObjects
kubectl get scaledobjects -n ecommerce -w

# Watch generated HPAs
kubectl get hpa -n ecommerce -w

# Watch pods scaling
kubectl get pods -n ecommerce -w

# Monitor all resources
kubectl get all -n ecommerce
```

### Detailed Status

```bash
# ScaledObject detailed status
kubectl describe scaledobject frontend-scaler -n ecommerce

# Generated HPA details
kubectl describe hpa keda-frontend-scaler -n ecommerce

# KEDA operator health
kubectl get pods -n keda -o wide
kubectl describe pod keda-operator-<pod-id> -n keda

# View metrics for HPA
kubectl top pods -n ecommerce
kubectl top nodes
```

### Metrics Export

```bash
# Export all ScaledObjects
kubectl get scaledobjects -n ecommerce -o yaml > keda-scalers-backup.yaml

# Export all HPAs
kubectl get hpa -n ecommerce -o yaml > hpa-status.yaml

# Export KEDA configuration
kubectl get all -n keda -o yaml > keda-operator-backup.yaml
```

## Optimization Tips

### 1. Threshold Tuning

```bash
# Start with conservative thresholds
# Monitor actual metrics under load
kubectl get hpa -n ecommerce -o custom-columns=NAME:.metadata.name,TARGETS:.status.currentMetrics[*].resource.current.averageUtilization

# Gradually adjust thresholds
kubectl patch scaledobject frontend-scaler -p '{"spec":{"triggers":[{"metadata":{"threshold":"150"}}]}}'
```

### 2. Stabilization Windows

```yaml
# Increase stabilization for cost savings
advanced:
  horizontalPodAutoscalerConfig:
    behavior:
      scaleDown:
        stabilizationWindowSeconds: 600 # 10 minutes
        policies:
          - type: Percent
            value: 50
            periodSeconds: 120
```

### 3. Cost Control

```yaml
# Limit maximum replicas
spec:
  maxReplicaCount: 5 # Prevent runaway scaling

  # Use reasonable minimum
  minReplicaCount: 1 # Allow zero if safe (fallback to 1)
```

### 4. Availability vs Cost

```yaml
# High availability (more resources, lower latency)
minReplicaCount: 3
maxReplicaCount: 20

# Cost optimization (fewer resources, higher latency risk)
minReplicaCount: 1
maxReplicaCount: 5
```

## Advanced Features

### 1. Multiple Triggers

KEDA evaluates all triggers and **scales to the maximum required replicas**:

```yaml
triggers:
  - type: prometheus # Returns 5 replicas needed
    metadata:
      threshold: "100"

  - type: cpu # Returns 8 replicas needed
    metadata:
      value: "75"

# Result: Scale to 8 replicas (maximum)
```

### 2. Fallback Mechanism

If all metrics become unavailable:

```yaml
fallbacks:
  - failureType: all
    replicas: 3 # Scale to 3 replicas when metrics fail
```

### 3. Graceful Degradation

The system continues scaling based on CPU/memory if custom metrics fail:

```yaml
triggers:
  - type: prometheus # Primary (may fail)
    metadata:
      query: "custom_metric"

  - type: cpu # Fallback (always available)
    metadata:
      value: "80"
```

## Integration with CI/CD

### GitOps Approach

Store KEDA manifests in Git:

```bash
# Repository structure
.
├── manifests/
│   ├── 06-keda-setup.yaml      # KEDA operator
│   └── 07-keda-scalers.yaml    # Scalers
├── scripts/
│   ├── deploy.sh               # Main deploy
│   └── deploy-keda.sh          # KEDA-specific
└── tests/
    └── test-keda.sh            # Test suite
```

### Automated Deployment

```bash
#!/bin/bash
# CI/CD pipeline step

# Deploy application
./scripts/deploy.sh kubectl ecommerce

# Deploy KEDA
./scripts/deploy-keda.sh ecommerce

# Run tests
./tests/test-keda.sh ecommerce 60

# Verify scaling
kubectl get scaledobjects -n ecommerce
kubectl get hpa -n ecommerce
```

### Helm Integration

```bash
# Add KEDA Helm repository
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# Install KEDA via Helm
helm install keda kedacore/keda \
  --namespace keda \
  --create-namespace \
  --set serviceAccount.create=true

# Install application
helm install myapp ./helm-chart -n ecommerce
```

## Rollback Plan

If KEDA causes issues:

```bash
# Option 1: Pause KEDA (keep HPA)
kubectl patch scaledobject frontend-scaler -p '{"spec":{"paused":true}}'

# Option 2: Delete ScaledObjects (revert to HPA)
kubectl delete scaledobjects -n ecommerce --all

# Option 3: Full rollback
kubectl delete -f manifests/07-keda-scalers.yaml
kubectl delete -f manifests/06-keda-setup.yaml

# HPA continues managing replicas
kubectl get hpa -n ecommerce
```

## Performance Impact

### Overhead

- KEDA operator: ~50-100MB memory, minimal CPU
- Metrics evaluation: ~30s intervals (default)
- HPA reconciliation: <1s

### Latency

- Metric evaluation to scaling: ~30-60 seconds
- Pod startup time: ~5-15 seconds (depends on app)
- Total scale-out latency: 35-75 seconds

### Cost

- KEDA operator: Minimal (~$5-10/month)
- Prometheus: ~50-100MB memory
- Additional nodes from scaling: Varies by workload

## References

- [KEDA Documentation](https://keda.sh/docs/)
- [ScaledObject API Reference](https://keda.sh/docs/latest/concepts/scaling-deployments/)
- [Available Scalers](https://keda.sh/docs/latest/scalers/)
- [Prometheus Querying](https://prometheus.io/docs/prometheus/latest/querying/)

## Summary

KEDA provides:

- ✅ Event-driven autoscaling beyond CPU/memory
- ✅ Multiple trigger support
- ✅ Custom business metrics
- ✅ Graceful fallback mechanism
- ✅ Production-ready reliability
- ✅ Easy integration with existing deployments

The implementation is backward compatible with HPA, allowing parallel testing and gradual migration.
