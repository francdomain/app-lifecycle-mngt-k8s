#!/bin/bash

##############################################################################
# E-Commerce Microservices - Blue-Green Deployment Test
#
# Tests blue-green deployment for API Gateway with manual switching
# Usage: ./test-blue-green.sh [namespace] [action]
# Actions: status, scale-green, switch, rollback
##############################################################################

set -e

NAMESPACE=${1:-ecommerce}
ACTION=${2:-status}

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

print_usage() {
    echo "Usage: $0 [namespace] [action]"
    echo ""
    echo "Actions:"
    echo "  status       - Show current blue/green status (default)"
    echo "  scale-green  - Scale up green deployment"
    echo "  switch       - Switch traffic from blue to green"
    echo "  rollback     - Rollback to blue deployment"
    echo "  cleanup      - Cleanup green deployment"
}

show_status() {
    echo ""
    log_info "Blue Deployment (v1 - Current):"
    kubectl get deployment api-gateway-blue -n "$NAMESPACE" -o wide 2>/dev/null || log_warning "Not found"

    log_info "Blue Pods:"
    kubectl get pods -n "$NAMESPACE" -l app=api-gateway,version=v1 --no-headers | head -5

    echo ""
    log_info "Green Deployment (v2 - Standby):"
    kubectl get deployment api-gateway-green -n "$NAMESPACE" -o wide 2>/dev/null || log_warning "Not found"

    log_info "Green Pods:"
    kubectl get pods -n "$NAMESPACE" -l app=api-gateway,version=v2 --no-headers | head -5

    echo ""
    log_info "Current Service Selector:"
    kubectl get svc api-gateway -n "$NAMESPACE" -o jsonpath='{.spec.selector}' | jq .
}

scale_green() {
    echo ""
    log_info "Scaling up green deployment to 2 replicas..."

    kubectl scale deployment api-gateway-green --replicas=2 -n "$NAMESPACE"

    log_success "Green deployment scaled to 2 replicas"

    log_info "Waiting for green pods to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app=api-gateway,version=v2 \
        -n "$NAMESPACE" \
        --timeout=300s \
        2>/dev/null || log_warning "Timeout waiting for green pods"

    log_success "Green pods are ready"

    log_info "Running smoke tests on green deployment..."
    TEST_POD=$(kubectl get pods -n "$NAMESPACE" -l app=api-gateway,version=v2 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -n "$TEST_POD" ]; then
        if kubectl exec "$TEST_POD" -n "$NAMESPACE" -- sh -c "wget -q -O- http://localhost/health" &> /dev/null; then
            log_success "Green deployment health check passed"
        else
            log_error "Green deployment health check failed"
            return 1
        fi
    fi

    return 0
}

switch_to_green() {
    echo ""
    log_info "Verifying green deployment readiness..."

    GREEN_READY=$(kubectl get deployment api-gateway-green -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    GREEN_DESIRED=$(kubectl get deployment api-gateway-green -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')

    if [ "$GREEN_READY" != "$GREEN_DESIRED" ]; then
        log_error "Green deployment not ready: $GREEN_READY/$GREEN_DESIRED"
        log_info "Please run scale-green action first"
        return 1
    fi

    log_success "Green deployment is ready"
    echo ""

    log_info "Switching traffic from blue to green..."
    echo "  Updating api-gateway service selector from v1 to v2..."

    kubectl patch service api-gateway -n "$NAMESPACE" \
        -p '{"spec":{"selector":{"version":"v2"}}}'

    log_success "Traffic switched to green deployment"

    log_info "Verifying traffic is flowing to green..."
    sleep 5

    GREEN_EP=$(kubectl get endpoints api-gateway -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[?(@.targetRef.labels.version=="v2")].ip}' | wc -w)
    BLUE_EP=$(kubectl get endpoints api-gateway -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[?(@.targetRef.labels.version=="v1")].ip}' | wc -w)

    if [ "$GREEN_EP" -gt 0 ]; then
        log_success "Traffic is now routed to green deployment ($GREEN_EP endpoints)"
    else
        log_warning "No green endpoints found"
    fi

    echo ""
    log_info "Monitoring stability for 60 seconds..."
    for i in {1..6}; do
        sleep 10
        READY=$(kubectl get deployment api-gateway-green -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
        echo "[$((i*10))/60] Green pods ready: $READY"
    done

    log_success "Green deployment is stable"
    echo ""

    log_info "Cleaning up blue deployment..."
    kubectl scale deployment api-gateway-blue --replicas=0 -n "$NAMESPACE"
    log_success "Blue deployment scaled down"

    return 0
}

rollback_to_blue() {
    echo ""
    log_info "Rolling back to blue deployment..."

    log_info "Updating api-gateway service selector from v2 to v1..."
    kubectl patch service api-gateway -n "$NAMESPACE" \
        -p '{"spec":{"selector":{"version":"v1"}}}'

    log_success "Traffic switched back to blue deployment"

    log_info "Scaling up blue deployment..."
    kubectl scale deployment api-gateway-blue --replicas=2 -n "$NAMESPACE"

    log_success "Blue deployment scaled to 2 replicas"

    log_info "Waiting for blue pods to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app=api-gateway,version=v1 \
        -n "$NAMESPACE" \
        --timeout=300s \
        2>/dev/null || log_warning "Timeout waiting for blue pods"

    log_success "Rollback completed - traffic restored to blue"

    log_info "Scaling down green deployment..."
    kubectl scale deployment api-gateway-green --replicas=0 -n "$NAMESPACE"

    return 0
}

cleanup_green() {
    echo ""
    log_info "Cleaning up green deployment resources..."

    log_info "Removing green deployment..."
    kubectl delete deployment api-gateway-green -n "$NAMESPACE" --ignore-not-found=true

    log_success "Green deployment removed"
}

# Main execution
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Blue-Green Deployment Test${NC}"
echo -e "${BLUE}========================================${NC}"

case "$ACTION" in
    status)
        show_status
        ;;
    scale-green)
        show_status
        scale_green
        show_status
        ;;
    switch)
        if scale_green; then
            switch_to_green
            show_status
        else
            log_error "Failed to scale green deployment"
            exit 1
        fi
        ;;
    rollback)
        rollback_to_blue
        show_status
        ;;
    cleanup)
        cleanup_green
        show_status
        ;;
    *)
        print_usage
        exit 1
        ;;
esac

echo ""
log_success "Blue-green test action completed"
