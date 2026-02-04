#!/bin/bash

##############################################################################
# E-Commerce Microservices - Canary Deployment Test
#
# Tests canary deployment for frontend with automatic rollout
# Usage: ./test-canary.sh [namespace]
##############################################################################

set -e

NAMESPACE=${1:-ecommerce}

# Color codes
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Canary Deployment Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if Flagger is installed
log_info "Checking for Flagger installation..."
if ! kubectl get namespace flagger-system &> /dev/null; then
    log_warning "Flagger is not installed"
    echo ""
    echo "To install Flagger:"
    echo "  helm repo add flagger https://flagger.app"
    echo "  helm repo update"
    echo "  helm install flagger flagger/flagger -n flagger-system --create-namespace"
    exit 1
fi

log_success "Flagger is installed"
echo ""

# Get current frontend deployment
log_info "Current Frontend Deployment Status:"
kubectl get deployment frontend -n "$NAMESPACE" -o wide
echo ""

# Show canary resource if it exists
log_info "Checking for Canary resource..."
if kubectl get canary frontend -n "$NAMESPACE" &> /dev/null; then
    log_success "Canary resource exists"
    echo ""
    log_info "Canary Configuration:"
    kubectl describe canary frontend -n "$NAMESPACE"
else
    log_warning "Canary resource not found"
    echo ""
    echo "To create a canary deployment, apply the deployment strategy manifest:"
    echo "  kubectl apply -f deployment-strategies/01-canary-bluegreen.yaml"
    exit 1
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Canary Rollout Process${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

log_info "Monitoring canary progress..."
echo "The canary deployment will proceed through these stages:"
echo "  1. 10% of traffic routed to canary"
echo "  2. Wait 5 minutes while monitoring metrics"
echo "  3. On success, increase to 25%"
echo "  4. Continue to 50%, 75%, and finally 100%"
echo "  5. On failure, automatic rollback"
echo ""

# Watch the deployment
log_info "Watching canary status (press Ctrl+C to stop)..."
kubectl get canary frontend -n "$NAMESPACE" --watch &
WATCH_PID=$!

# Monitor for 5 minutes, checking status
for i in {1..5}; do
    sleep 60

    # Get canary status
    PHASE=$(kubectl get canary frontend -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    WEIGHT=$(kubectl get canary frontend -n "$NAMESPACE" -o jsonpath='{.status.canaryWeight}' 2>/dev/null || echo "0")
    ITERATIONS=$(kubectl get canary frontend -n "$NAMESPACE" -o jsonpath='{.status.iterations}' 2>/dev/null || echo "0")

    echo "[$i/5] Phase: $PHASE | Canary Weight: $WEIGHT% | Iterations: $ITERATIONS"
done

kill $WATCH_PID 2>/dev/null || true

echo ""
log_success "Monitoring completed"

# Final status
echo ""
log_info "Final Canary Status:"
kubectl get canary frontend -n "$NAMESPACE" -o jsonpath='{.status}' | jq . 2>/dev/null || \
    kubectl describe canary frontend -n "$NAMESPACE"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Results${NC}"
echo -e "${BLUE}========================================${NC}"

# Check final phase
FINAL_PHASE=$(kubectl get canary frontend -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

if [ "$FINAL_PHASE" == "Succeeded" ]; then
    log_success "Canary deployment succeeded!"
elif [ "$FINAL_PHASE" == "Failed" ]; then
    log_error "Canary deployment failed - automatic rollback performed"
elif [ "$FINAL_PHASE" == "Progressing" ]; then
    log_warning "Canary deployment is still in progress"
else
    log_warning "Canary phase: $FINAL_PHASE"
fi

echo ""
log_info "Final Frontend Pods:"
kubectl get pods -n "$NAMESPACE" -l app=frontend -o wide
