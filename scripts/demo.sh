#!/bin/bash

##############################################################################
# E-Commerce Microservices - Demo Script
#
# Demonstrates key features: deployment, scaling, and rollback
# Usage: ./demo.sh [namespace]
##############################################################################

set -e

NAMESPACE=${1:-ecommerce}

# Color codes
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_demo() {
    echo -e "${MAGENTA}==>${NC} $1"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_step() {
    echo -e "${YELLOW}Step: $1${NC}"
}

pause_demo() {
    read -p "$(echo -e ${BLUE}Press Enter to continue...${NC})" -t 5 || true
    echo ""
}

clear_screen() {
    clear || printf '\033[2J\033[3J\033[1;1H'
}

echo -e "${BLUE}========================================${NC}"
echo -e "${MAGENTA}E-Commerce Microservices Demo${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check prerequisites
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_info "Namespace not found. Deploying application..."
    ./deploy.sh kubectl "$NAMESPACE"
fi

log_success "Deployment verified"
echo ""

# Demo 1: Show current state
log_demo "Demo 1: Current Deployment Status"
echo ""
log_step "Show all running pods"
echo ""
kubectl get pods -n "$NAMESPACE" -o wide
echo ""
pause_demo

# Demo 2: Show services
log_demo "Demo 2: Service Discovery"
echo ""
log_step "Show all services and endpoints"
echo ""
kubectl get svc -n "$NAMESPACE" -o wide
echo ""
pause_demo

# Demo 3: Show HPA scaling
log_demo "Demo 3: Horizontal Pod Autoscaling"
echo ""
log_step "Show HPA configuration"
echo ""
kubectl get hpa -n "$NAMESPACE"
echo ""
pause_demo

# Demo 4: Load test
log_demo "Demo 4: Load Testing & Autoscaling"
echo ""
log_step "Generating load on frontend..."
echo ""

# Start load generator
kubectl run load-gen-demo-$RANDOM \
  --image=busybox:latest \
  --restart=Never \
  -n "$NAMESPACE" \
  --quiet \
  -- /bin/sh -c "while true; do wget -q -O- http://frontend/ > /dev/null; done" &

LOAD_PID=$!
echo "Load generator started (PID: $LOAD_PID)"
echo ""

log_step "Monitoring HPA activity (30 seconds)..."
echo ""
for i in {1..3}; do
    sleep 10
    echo "=== Status at 10s intervals ==="
    kubectl get hpa frontend-hpa -n "$NAMESPACE" --no-headers
    kubectl get pods -n "$NAMESPACE" -l app=frontend --no-headers | wc -l | xargs echo "Frontend pods:"
done

# Cleanup load generator
log_info "Stopping load generator..."
kubectl delete pod -l "run=load-gen-demo" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true

echo ""
pause_demo

# Demo 5: Update and rollback
log_demo "Demo 5: Deployment Updates & Rollback"
echo ""
log_step "Show current deployment revision"
echo ""
kubectl rollout history deployment/frontend -n "$NAMESPACE" || echo "No rollout history available"
echo ""

log_step "Update frontend image (rolling update)"
echo ""
kubectl set image deployment/frontend \
  frontend=nginx:latest \
  -n "$NAMESPACE" \
  --record=true

echo "Rollout in progress..."
kubectl rollout status deployment/frontend -n "$NAMESPACE" --timeout=5m || true
echo ""
pause_demo

log_step "Rollback to previous version"
echo ""
kubectl rollout undo deployment/frontend -n "$NAMESPACE"
echo ""
kubectl rollout status deployment/frontend -n "$NAMESPACE" --timeout=5m || true
log_success "Rolled back to previous version"
echo ""
pause_demo

# Demo 6: Configuration updates
log_demo "Demo 6: Configuration Management"
echo ""
log_step "Show current ConfigMaps"
echo ""
kubectl get configmap service-urls -n "$NAMESPACE" -o yaml
echo ""
pause_demo

log_step "Update ConfigMap and restart pods"
echo ""
kubectl set env deployment/frontend \
  UPDATED_AT="$(date)" \
  -n "$NAMESPACE"

kubectl rollout restart deployment/frontend -n "$NAMESPACE"
kubectl rollout status deployment/frontend -n "$NAMESPACE" --timeout=5m || true
log_success "Configuration updated"
echo ""

# Demo 7: Blue-Green overview
log_demo "Demo 7: Deployment Strategies"
echo ""
log_step "Show available deployment strategy manifests"
echo ""
ls -lah ../deployment-strategies/
echo ""
pause_demo

log_step "Canary deployment configuration"
echo ""
echo "Canary deployments use Flagger for progressive rollout:"
echo "  - 10% of traffic → 5 min wait"
echo "  - 25% of traffic → 5 min wait"
echo "  - 50% of traffic → 5 min wait"
echo "  - 75% of traffic → 5 min wait"
echo "  - 100% of traffic (promotion)"
echo ""

log_step "Blue-Green deployment configuration"
echo ""
echo "Blue-Green uses manual switching:"
echo "  1. Scale up 'green' (new version)"
echo "  2. Run smoke tests"
echo "  3. Switch traffic service selector"
echo "  4. Keep 'blue' for instant rollback"
echo ""
pause_demo

# Demo 8: Monitoring and troubleshooting
log_demo "Demo 8: Monitoring & Troubleshooting"
echo ""
log_step "Pod resource usage"
echo ""
kubectl top pods -n "$NAMESPACE" 2>/dev/null || echo "Metrics not available (install metrics-server)"
echo ""

log_step "Recent events"
echo ""
kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10
echo ""
pause_demo

# Summary
clear_screen
echo -e "${BLUE}========================================${NC}"
echo -e "${MAGENTA}Demo Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo "Key Features Demonstrated:"
echo "  ✓ Pod deployment and scaling"
echo "  ✓ Service discovery and load balancing"
echo "  ✓ Horizontal Pod Autoscaling (HPA)"
echo "  ✓ Load testing"
echo "  ✓ Rolling updates and rollbacks"
echo "  ✓ Configuration management"
echo "  ✓ Deployment strategies"
echo "  ✓ Monitoring and troubleshooting"
echo ""

echo "Next Steps:"
echo "  1. Run full test suite:      ./tests/verify-deployment.sh"
echo "  2. Run integration tests:    ./tests/integration-tests.sh"
echo "  3. Test canary deployment:  ./tests/test-canary.sh"
echo "  4. Test blue-green:         ./tests/test-blue-green.sh"
echo "  5. View application:        kubectl port-forward svc/frontend 8080:80 -n $NAMESPACE"
echo ""

log_success "Demo completed successfully!"
