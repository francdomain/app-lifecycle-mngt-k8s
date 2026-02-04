#!/bin/bash

##############################################################################
# E-Commerce Microservices - Deployment Verification Script
#
# This script verifies all deployment components are working correctly
# Usage: ./verify-deployment.sh [namespace]
##############################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE=${1:-ecommerce}
TIMEOUT=30

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    ((PASSED++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
    ((WARNINGS++))
}

# Main script
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}E-Commerce Deployment Verification${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 1. Check Namespace
echo -e "${BLUE}1. Checking Namespace...${NC}"
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_success "Namespace '$NAMESPACE' exists"
else
    log_error "Namespace '$NAMESPACE' not found"
    exit 1
fi
echo ""

# 2. Check ConfigMaps
echo -e "${BLUE}2. Checking ConfigMaps...${NC}"
CONFIGMAPS=("service-urls" "feature-flags" "api-gateway-config" "frontend-html")
for cm in "${CONFIGMAPS[@]}"; do
    if kubectl get configmap "$cm" -n "$NAMESPACE" &> /dev/null; then
        log_success "ConfigMap '$cm' exists"
    else
        log_error "ConfigMap '$cm' not found"
    fi
done
echo ""

# 3. Check Secrets
echo -e "${BLUE}3. Checking Secrets...${NC}"
if kubectl get secret api-keys -n "$NAMESPACE" &> /dev/null; then
    log_success "Secret 'api-keys' exists"
else
    log_error "Secret 'api-keys' not found"
fi
echo ""

# 4. Check Services
echo -e "${BLUE}4. Checking Services...${NC}"
SERVICES=("frontend" "api-gateway" "product-service" "order-service")
for svc in "${SERVICES[@]}"; do
    if kubectl get service "$svc" -n "$NAMESPACE" &> /dev/null; then
        log_success "Service '$svc' exists"

        # Check endpoints
        ENDPOINTS=$(kubectl get endpoints "$svc" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w)
        if [ "$ENDPOINTS" -gt 0 ]; then
            log_success "  └─ Has $ENDPOINTS endpoints"
        else
            log_warning "  └─ No endpoints found (pods may not be ready)"
        fi
    else
        log_error "Service '$svc' not found"
    fi
done
echo ""

# 5. Check Deployments
echo -e "${BLUE}5. Checking Deployments...${NC}"
DEPLOYMENTS=("frontend" "api-gateway" "product-service" "order-service")
for dep in "${DEPLOYMENTS[@]}"; do
    if kubectl get deployment "$dep" -n "$NAMESPACE" &> /dev/null; then
        READY=$(kubectl get deployment "$dep" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
        DESIRED=$(kubectl get deployment "$dep" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')

        if [ "$READY" == "$DESIRED" ]; then
            log_success "Deployment '$dep' ready ($READY/$DESIRED)"
        else
            log_warning "Deployment '$dep' not fully ready ($READY/$DESIRED)"
        fi
    else
        log_error "Deployment '$dep' not found"
    fi
done
echo ""

# 6. Check Pods
echo -e "${BLUE}6. Checking Pods...${NC}"
log_info "Pod Status:"
kubectl get pods -n "$NAMESPACE" -o wide
echo ""

TOTAL_PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers | wc -l)
RUNNING_PODS=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Running --no-headers | wc -l)
READY_PODS=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' | grep -c "True" || true)

if [ "$RUNNING_PODS" == "$TOTAL_PODS" ]; then
    log_success "All $RUNNING_PODS pods are running"
else
    log_warning "Only $RUNNING_PODS/$TOTAL_PODS pods running"
fi

if [ "$READY_PODS" == "$TOTAL_PODS" ]; then
    log_success "All $READY_PODS pods are ready"
else
    log_warning "Only $READY_PODS/$TOTAL_PODS pods ready"
fi
echo ""

# 7. Check HPAs
echo -e "${BLUE}7. Checking Horizontal Pod Autoscalers...${NC}"
HPAS=("frontend-hpa" "api-gateway-hpa" "product-service-hpa" "order-service-hpa")
for hpa in "${HPAS[@]}"; do
    if kubectl get hpa "$hpa" -n "$NAMESPACE" &> /dev/null; then
        CURRENT=$(kubectl get hpa "$hpa" -n "$NAMESPACE" -o jsonpath='{.status.currentReplicas}')
        MIN=$(kubectl get hpa "$hpa" -n "$NAMESPACE" -o jsonpath='{.spec.minReplicas}')
        MAX=$(kubectl get hpa "$hpa" -n "$NAMESPACE" -o jsonpath='{.spec.maxReplicas}')

        log_success "HPA '$hpa' exists (current: $CURRENT, min: $MIN, max: $MAX)"
    else
        log_warning "HPA '$hpa' not found"
    fi
done
echo ""

# 8. Check Health of Pods
echo -e "${BLUE}8. Checking Pod Health...${NC}"
for pod in $(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'); do
    PHASE=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    READY=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')

    if [ "$PHASE" == "Running" ] && [ "$READY" == "True" ]; then
        log_success "Pod '$pod' is healthy"
    elif [ "$PHASE" == "Running" ]; then
        log_warning "Pod '$pod' is running but not ready"
    else
        log_error "Pod '$pod' is in $PHASE state"
    fi
done
echo ""

# 9. Resource Usage
echo -e "${BLUE}9. Checking Resource Usage...${NC}"
if kubectl top pod -n "$NAMESPACE" &> /dev/null; then
    echo "Pod Resource Usage:"
    kubectl top pod -n "$NAMESPACE"
    echo ""
    log_success "Metrics available"
else
    log_warning "Metrics not available (metrics-server may not be installed)"
fi
echo ""

# 10. Network Connectivity Check
echo -e "${BLUE}10. Checking Network Connectivity...${NC}"
log_info "Testing internal connectivity (this may take a moment)..."

# Get a running pod for testing
TEST_POD=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$TEST_POD" ]; then
    log_info "Using pod '$TEST_POD' for connectivity test"

    # Test service discovery
    if kubectl exec "$TEST_POD" -n "$NAMESPACE" -- sh -c "wget -q -O- http://frontend/health" &> /dev/null; then
        log_success "Frontend service is accessible"
    else
        log_warning "Could not reach frontend service"
    fi

    if kubectl exec "$TEST_POD" -n "$NAMESPACE" -- sh -c "wget -q -O- http://product-service:8080/status/200" &> /dev/null; then
        log_success "Product service is accessible"
    else
        log_warning "Could not reach product service"
    fi
else
    log_warning "No running pods found for connectivity test"
fi
echo ""

# 11. Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Verification Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All critical checks passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some checks failed. Please review the output above.${NC}"
    exit 1
fi
