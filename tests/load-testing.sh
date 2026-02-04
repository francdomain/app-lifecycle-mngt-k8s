#!/bin/bash

##############################################################################
# E-Commerce Microservices - Load Testing Script
#
# Generates load to test HPA and autoscaling behavior
# Usage: ./load-testing.sh [namespace] [service] [duration]
##############################################################################

set -e

# Configuration
NAMESPACE=${1:-ecommerce}
SERVICE=${2:-frontend}
DURATION=${3:-300}  # 5 minutes default
CONCURRENT=${4:-10}
RATE=${5:-100}  # requests per second

# Color codes
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}E-Commerce Load Testing${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

log_info "Configuration:"
echo "  Namespace: $NAMESPACE"
echo "  Service: $SERVICE"
echo "  Duration: ${DURATION}s"
echo "  Concurrent connections: $CONCURRENT"
echo "  Requests per second: $RATE"
echo ""

# Get service information
log_info "Getting service information..."
SERVICE_IP=$(kubectl get svc "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || \
             kubectl get svc "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)

if [ -z "$SERVICE_IP" ]; then
    log_info "Could not get LoadBalancer IP, using service DNS"
    SERVICE_URL="http://${SERVICE}.${NAMESPACE}.svc.cluster.local/"
else
    SERVICE_URL="http://${SERVICE_IP}/"
fi

echo "  URL: $SERVICE_URL"
echo ""

# Start load testing
log_info "Starting load test..."
log_info "Opening new terminal for HPA monitoring..."

# Run load test in background
log_info "Generating load with following parameters:"
echo "  - Target: $SERVICE_URL"
echo "  - Method: GET"
echo "  - Concurrent connections: $CONCURRENT"
echo "  - Rate: $RATE req/s"
echo "  - Duration: ${DURATION}s"
echo ""

log_info "Launching load generator pod..."
kubectl run load-generator-$RANDOM \
  --image=busybox:latest \
  --restart=Never \
  -n "$NAMESPACE" \
  --quiet \
  -- /bin/sh -c "
    echo 'Starting load test for ${DURATION}s'
    START=\$(date +%s)
    while [ \$(((\$(date +%s) - \$START))) -lt $DURATION ]; do
      wget -q -O- $SERVICE_URL > /dev/null 2>&1 &
    done
    wait
    echo 'Load test completed'
  " &

LOAD_POD_PID=$!

log_info "Load generator started with PID $LOAD_POD_PID"
echo ""

# Monitor HPA in another terminal window
log_info "HPA Status (updating every 5 seconds):"
for i in $(seq 0 5 $DURATION); do
    if [ $i -eq 0 ]; then
        kubectl get hpa "${SERVICE}-hpa" -n "$NAMESPACE" 2>/dev/null || echo "HPA not found"
    fi
    sleep 5

    # Show current status
    CURRENT=$(kubectl get hpa "${SERVICE}-hpa" -n "$NAMESPACE" -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo "N/A")
    DESIRED=$(kubectl get hpa "${SERVICE}-hpa" -n "$NAMESPACE" -o jsonpath='{.status.desiredReplicas}' 2>/dev/null || echo "N/A")
    CPU=$(kubectl get hpa "${SERVICE}-hpa" -n "$NAMESPACE" -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || echo "N/A")

    echo "[$i/$DURATION] Current: $CURRENT, Desired: $DESIRED, CPU: ${CPU}%"
done

log_success "Load test completed!"
echo ""

# Final HPA status
log_info "Final HPA Status:"
kubectl get hpa "${SERVICE}-hpa" -n "$NAMESPACE" 2>/dev/null || true
echo ""

# Pod count comparison
log_info "Final Pod Count for $SERVICE:"
kubectl get pods -n "$NAMESPACE" -l app="$SERVICE" --no-headers | wc -l
echo ""

# Clean up load generators
log_info "Cleaning up load generators..."
kubectl delete pods -n "$NAMESPACE" -l "app=load-generator" --ignore-not-found=true 2>/dev/null || true

log_success "Load test completed successfully!"
