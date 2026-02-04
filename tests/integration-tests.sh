#!/bin/bash

##############################################################################
# E-Commerce Microservices - Integration Test Suite
#
# Comprehensive integration tests for all services
# Usage: ./integration-tests.sh [namespace]
##############################################################################

set -e

NAMESPACE=${1:-ecommerce}
TESTS_PASSED=0
TESTS_FAILED=0

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
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((TESTS_FAILED++))
}

test_case() {
    echo ""
    echo -e "${BLUE}TEST: $1${NC}"
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Integration Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Test 1: Namespace exists
test_case "Namespace Existence"
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_success "Namespace '$NAMESPACE' exists"
else
    log_error "Namespace '$NAMESPACE' does not exist"
    exit 1
fi

# Test 2: All services are running
test_case "Services Running"
SERVICES=("frontend" "api-gateway" "product-service" "order-service")
for svc in "${SERVICES[@]}"; do
    if kubectl get service "$svc" -n "$NAMESPACE" &> /dev/null; then
        ENDPOINTS=$(kubectl get endpoints "$svc" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w)
        if [ "$ENDPOINTS" -gt 0 ]; then
            log_success "Service '$svc' has $ENDPOINTS ready endpoints"
        else
            log_error "Service '$svc' has no ready endpoints"
        fi
    else
        log_error "Service '$svc' not found"
    fi
done

# Test 3: All deployments are ready
test_case "Deployments Ready"
DEPLOYMENTS=("frontend" "api-gateway" "product-service" "order-service")
for dep in "${DEPLOYMENTS[@]}"; do
    if kubectl get deployment "$dep" -n "$NAMESPACE" &> /dev/null; then
        READY=$(kubectl get deployment "$dep" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
        DESIRED=$(kubectl get deployment "$dep" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')

        if [ "$READY" == "$DESIRED" ] && [ "$DESIRED" -gt 0 ]; then
            log_success "Deployment '$dep' ready ($READY/$DESIRED)"
        else
            log_error "Deployment '$dep' not ready ($READY/$DESIRED)"
        fi
    else
        log_error "Deployment '$dep' not found"
    fi
done

# Test 4: ConfigMaps exist
test_case "ConfigMaps"
CONFIGMAPS=("service-urls" "feature-flags" "api-gateway-config" "frontend-html")
for cm in "${CONFIGMAPS[@]}"; do
    if kubectl get configmap "$cm" -n "$NAMESPACE" &> /dev/null; then
        log_success "ConfigMap '$cm' exists"
    else
        log_error "ConfigMap '$cm' not found"
    fi
done

# Test 5: Secrets exist
test_case "Secrets"
if kubectl get secret api-keys -n "$NAMESPACE" &> /dev/null; then
    API_KEY=$(kubectl get secret api-keys -n "$NAMESPACE" -o jsonpath='{.data.API_KEY}' | base64 -d 2>/dev/null)
    if [ -n "$API_KEY" ]; then
        log_success "Secret 'api-keys' exists with API_KEY"
    else
        log_error "API_KEY not found in secret"
    fi
else
    log_error "Secret 'api-keys' not found"
fi

# Test 6: HPAs exist and configured
test_case "Horizontal Pod Autoscalers"
HPAS=("frontend-hpa" "api-gateway-hpa" "product-service-hpa" "order-service-hpa")
for hpa in "${HPAS[@]}"; do
    if kubectl get hpa "$hpa" -n "$NAMESPACE" &> /dev/null; then
        MIN=$(kubectl get hpa "$hpa" -n "$NAMESPACE" -o jsonpath='{.spec.minReplicas}')
        MAX=$(kubectl get hpa "$hpa" -n "$NAMESPACE" -o jsonpath='{.spec.maxReplicas}')
        log_success "HPA '$hpa' exists (min: $MIN, max: $MAX)"
    else
        log_error "HPA '$hpa' not found"
    fi
done

# Test 7: Pod health checks
test_case "Pod Health Checks"
for pod in $(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' | head -4); do
    READY=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')

    if [ "$READY" == "True" ]; then
        # Check for health check configuration
        PROBES=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].livenessProbe}')
        if [ -n "$PROBES" ]; then
            log_success "Pod '$pod' has health checks configured"
        else
            log_error "Pod '$pod' has no health checks"
        fi
    else
        log_error "Pod '$pod' is not ready"
    fi
done

# Test 8: Network connectivity
test_case "Network Connectivity"
TEST_POD=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$TEST_POD" ]; then
    if kubectl exec "$TEST_POD" -n "$NAMESPACE" -- sh -c "wget -q -O- http://frontend/health" &> /dev/null; then
        log_success "Frontend service is accessible from pod"
    else
        log_error "Cannot reach frontend service"
    fi

    if kubectl exec "$TEST_POD" -n "$NAMESPACE" -- sh -c "wget -q -O- http://product-service:8080/status/200" &> /dev/null; then
        log_success "Product service is accessible from pod"
    else
        log_error "Cannot reach product service"
    fi

    if kubectl exec "$TEST_POD" -n "$NAMESPACE" -- sh -c "wget -q -O- http://order-service:8080/status/200" &> /dev/null; then
        log_success "Order service is accessible from pod"
    else
        log_error "Cannot reach order service"
    fi
else
    log_error "No running pods found for connectivity test"
fi

# Test 9: Resource limits
test_case "Resource Configuration"
for dep in "frontend" "api-gateway"; do
    LIMITS=$(kubectl get deployment "$dep" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}')
    REQUESTS=$(kubectl get deployment "$dep" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}')

    if [ -n "$LIMITS" ] && [ -n "$REQUESTS" ]; then
        log_success "Deployment '$dep' has resource requests ($REQUESTS) and limits ($LIMITS)"
    else
        log_error "Deployment '$dep' missing resource configuration"
    fi
done

# Test 10: Graceful shutdown configuration
test_case "Graceful Shutdown"
for dep in "frontend" "api-gateway"; do
    GRACE=$(kubectl get deployment "$dep" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}')

    if [ -n "$GRACE" ] && [ "$GRACE" -gt 0 ]; then
        log_success "Deployment '$dep' has termination grace period: ${GRACE}s"
    else
        log_error "Deployment '$dep' missing graceful shutdown configuration"
    fi
done

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Results Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All integration tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed. Please review the output above.${NC}"
    exit 1
fi
