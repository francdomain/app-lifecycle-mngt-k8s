# KEDA Quick Reference

## Installation

```bash
# One-command installation
./scripts/deploy-keda.sh ecommerce

# Or with explicit namespace
./scripts/deploy-keda.sh my-namespace

# Manual installation
kubectl apply -f manifests/06-keda-setup.yaml
kubectl apply -f manifests/07-keda-scalers.yaml
```

## Verification

```bash
# Check KEDA operator
kubectl get pods -n keda

# Verify ScaledObjects
kubectl get scaledobjects -n ecommerce

# View generated HPAs
kubectl get hpa -n ecommerce

# Monitor scaling
kubectl get pods -n ecommerce --watch
```

## Common Commands

### Monitoring

```bash
# Real-time ScaledObject status
kubectl get scaledobjects -n ecommerce -w

# Detailed ScaledObject info
kubectl describe scaledobject frontend-scaler -n ecommerce

# View metric values
kubectl get hpa keda-frontend-scaler -n ecommerce -o yaml

# Recent events
kubectl get events -n ecommerce --sort-by='.lastTimestamp' | tail -10
```

### Debugging

```bash
# KEDA operator logs
kubectl logs -n keda -l app=keda -f

# ScaledObject conditions
kubectl describe scaledobject frontend-scaler -n ecommerce | grep -A 10 "Status:"

# Prometheus connectivity test
kubectl run -it --rm --restart=Never --image=curlimages/curl -- \
  curl http://prometheus:9090/api/v1/query?query=up

# Check current replicas
kubectl get deployments -n ecommerce --watch
```

### Configuration Updates

```bash
# Update ScaledObject
kubectl apply -f manifests/07-keda-scalers.yaml

# Patch a trigger threshold
kubectl patch scaledobject frontend-scaler -p '{"spec":{"triggers":[{"metadata":{"threshold":"150"}}]}}'

# Pause/resume scaling
kubectl patch scaledobject frontend-scaler -p '{"spec":{"paused":true}}'
kubectl patch scaledobject frontend-scaler -p '{"spec":{"paused":false}}'

# Change min/max replicas
kubectl patch scaledobject frontend-scaler -p '{"spec":{"minReplicaCount":3,"maxReplicaCount":15}}'
```

## ScaledObjects Summary

| Service             | Min | Max | Primary Metric | Threshold |
| ------------------- | --- | --- | -------------- | --------- |
| **Frontend**        | 2   | 10  | HTTP req/sec   | >100      |
| **API Gateway**     | 2   | 8   | HTTP req/sec   | >500      |
| **Product Service** | 2   | 6   | DB latency     | >500ms    |
| **Order Service**   | 2   | 6   | Queue depth    | >50       |

## Scaling Behavior

### Frontend

- **Up**: 100% increase / 30 sec
- **Down**: 50% decrease / 60 sec

### API Gateway

- **Up**: 100% increase / 30 sec
- **Down**: 50% decrease / 60 sec

### Product Service

- **Up**: 50% increase / 60 sec
- **Down**: 25% decrease / 120 sec

### Order Service

- **Up**: 100% increase / 30 sec
- **Down**: 50% decrease / 60 sec

## Testing

```bash
# Run KEDA test suite (5 minute test)
./tests/test-keda.sh ecommerce 300

# Generate load for manual testing
kubectl run -n ecommerce load-test --image=busybox -it --rm -- \
  /bin/sh -c "while sleep 1; do wget -q -O- http://frontend; done"

# Monitor scaling during load test
kubectl get pods,hpa -n ecommerce -w
```

## Troubleshooting

### ScaledObject Not Scaling

```bash
# Check status
kubectl describe scaledobject frontend-scaler -n ecommerce

# View conditions
kubectl get scaledobjects -n ecommerce -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[*].type}{"\t"}{.status.conditions[*].message}{"\n"}{end}'

# Check KEDA operator
kubectl logs -n keda -l app=keda | grep -i error
```

### Prometheus Metrics Not Found

```bash
# Test Prometheus connection
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Visit http://localhost:9090 and test metric in UI

# Or use curl
kubectl run -it --rm --restart=Never --image=curlimages/curl -- \
  curl 'http://prometheus:9090/api/v1/query?query=http_requests_total'
```

### HPA Not Generated

```bash
# Check KEDA operator logs
kubectl logs -n keda -l app=keda | grep -i "hpa\|error"

# Verify ScaledObject syntax
kubectl apply -f manifests/07-keda-scalers.yaml --dry-run=client -o yaml

# Check RBAC permissions
kubectl auth can-i create hpa --as=system:serviceaccount:keda:keda-operator -n ecommerce
```

## Performance Tuning

### Increase Responsiveness (Scale Faster)

```yaml
# Reduce stabilization window
advanced:
  horizontalPodAutoscalerConfig:
    behavior:
      scaleUp:
        stabilizationWindowSeconds: 0 # Scale immediately
        policies:
          - type: Percent
            value: 100
            periodSeconds: 15 # More frequent checks
```

### Reduce Cost (Scale Slower)

```yaml
# Increase stabilization window
advanced:
  horizontalPodAutoscalerConfig:
    behavior:
      scaleDown:
        stabilizationWindowSeconds: 600 # Wait 10 minutes
        policies:
          - type: Percent
            value: 25 # Scale down slowly
            periodSeconds: 180
```

### Balance Performance and Cost

```yaml
# Moderate settings
scaleUp:
  stabilizationWindowSeconds: 60
  policies:
    - type: Percent
      value: 50
      periodSeconds: 60

scaleDown:
  stabilizationWindowSeconds: 300
  policies:
    - type: Percent
      value: 50
      periodSeconds: 60
```

## Migration from HPA

### 1. Test KEDA in Parallel

```bash
# Keep existing HPA
kubectl get hpa -n ecommerce

# Add KEDA ScaledObjects
kubectl apply -f manifests/07-keda-scalers.yaml

# Monitor both systems
kubectl get hpa,scaledobjects -n ecommerce -w
```

### 2. Compare Behavior

```bash
# Check HPA scaling decisions
kubectl get hpa -n ecommerce -o custom-columns=NAME:.metadata.name,CURRENT:.status.currentReplicas,DESIRED:.status.desiredReplicas

# Check KEDA scaling decisions
kubectl get scaledobjects -n ecommerce -o custom-columns=NAME:.metadata.name,SCALETARGET:.spec.scaleTargetRef.name,MIN:.spec.minReplicaCount,MAX:.spec.maxReplicaCount
```

### 3. Switch to KEDA

```bash
# When confident in KEDA behavior
kubectl delete hpa -n ecommerce -l app=ecommerce

# KEDA continues scaling
kubectl get hpa -n ecommerce  # KEDA-generated HPAs still exist
```

### 4. Rollback if Needed

```bash
# Restore HPA
kubectl apply -f manifests/05-hpa.yaml

# Pause KEDA (keeps HPA)
kubectl patch scaledobject -all -p '{"spec":{"paused":true}}'
```

## Files Reference

| File                             | Purpose                      |
| -------------------------------- | ---------------------------- |
| `manifests/06-keda-setup.yaml`   | KEDA operator and components |
| `manifests/07-keda-scalers.yaml` | ScaledObject configurations  |
| `scripts/deploy-keda.sh`         | Installation script          |
| `tests/test-keda.sh`             | Test suite                   |
| `docs/KEDA_SETUP.md`             | Detailed setup guide         |
| `docs/KEDA_INTEGRATION.md`       | Integration guide            |

## Key Metrics by Service

### Frontend

```promql
sum(rate(nginx_http_requests_total{job="frontend"}[30s]))
```

### API Gateway

```promql
sum(rate(nginx_http_requests_total{job="api-gateway"}[30s]))
histogram_quantile(0.95, nginx_http_request_duration_seconds_bucket)
```

### Product Service

```promql
histogram_quantile(0.95, db_query_duration_seconds_bucket)
sum(rate(http_requests_total{service="product-service"}[30s]))
```

### Order Service

```promql
sum(increase(orders_pending_total[5m]))
sum(rate(http_requests_total{service="order-service", method="POST"}[30s]))
histogram_quantile(0.99, order_processing_duration_seconds_bucket)
```

## Resources

- [KEDA Documentation](https://keda.sh)
- [KEDA Scalers Reference](https://keda.sh/docs/latest/scalers/)
- [Prometheus Query Functions](https://prometheus.io/docs/prometheus/latest/querying/functions/)
- [Kubernetes Autoscaling Docs](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)

---

**Version**: 1.0
**Last Updated**: 2026-02-04
**KEDA Version**: 2.13+
