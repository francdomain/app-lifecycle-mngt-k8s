#!/bin/bash

##############################################################################
# E-Commerce Microservices - Quick Deployment Script
#
# Deploys the entire application with a single command
# Usage: ./deploy.sh [method] [namespace]
# Methods: kubectl, helm
##############################################################################

set -e

METHOD=${1:-kubectl}
NAMESPACE=${2:-ecommerce}

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

print_usage() {
    echo "Usage: $0 [method] [namespace]"
    echo ""
    echo "Methods:"
    echo "  kubectl - Deploy using kubectl apply (default)"
    echo "  helm    - Deploy using Helm chart"
    echo ""
    echo "Examples:"
    echo "  $0 kubectl ecommerce"
    echo "  $0 helm production"
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}E-Commerce Application Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is not installed"
    exit 1
fi

log_success "kubectl is available"

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

log_success "Connected to Kubernetes cluster"
echo ""

# Deploy using specified method
case "$METHOD" in
    kubectl)
        log_info "Deploying using kubectl method..."
        echo ""

        log_info "Step 1: Applying namespace..."
        kubectl apply -f manifests/00-namespace.yaml
        log_success "Namespace created"
        echo ""

        log_info "Step 2: Creating ConfigMaps from configuration files..."
        ./scripts/create-configmaps.sh "$NAMESPACE"
        log_success "ConfigMaps created"
        echo ""

        log_info "Step 3: Applying Secrets..."
        kubectl apply -f manifests/02-secrets.yaml
        log_success "Secrets created"
        echo ""

        log_info "Step 4: Applying Services..."
        kubectl apply -f manifests/03-services.yaml
        log_success "Services created"
        echo ""

        log_info "Step 5: Applying Deployments..."
        kubectl apply -f manifests/04-deployments.yaml
        log_success "Deployments created"
        echo ""

        log_info "Step 6: Applying HPAs..."
        kubectl apply -f manifests/05-hpa.yaml
        log_success "HPAs created"
        echo ""

        ;;
    helm)
        log_info "Deploying using Helm method..."
        echo ""

        # Check if Helm is available
        if ! command -v helm &> /dev/null; then
            log_error "Helm is not installed"
            exit 1
        fi

        log_success "Helm is available"
        echo ""

        log_info "Installing Helm chart..."
        helm install ecommerce-app ./helm-chart \
            -n "$NAMESPACE" \
            --create-namespace

        log_success "Helm chart installed"
        echo ""

        ;;
    *)
        print_usage
        exit 1
        ;;
esac

# Wait for deployments to be ready
log_info "Waiting for deployments to be ready..."
echo ""

DEPLOYMENTS=("frontend" "api-gateway" "product-service" "order-service")
for dep in "${DEPLOYMENTS[@]}"; do
    log_info "Waiting for $dep deployment..."
    kubectl rollout status deployment "$dep" -n "$NAMESPACE" --timeout=5m || {
        log_error "Timeout waiting for $dep to be ready"
        exit 1
    }
    log_success "$dep is ready"
done

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deployment Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

log_success "All deployments completed successfully!"
echo ""

# Display deployment info
log_info "Services:"
kubectl get services -n "$NAMESPACE" -o wide
echo ""

log_info "Pods:"
kubectl get pods -n "$NAMESPACE" -o wide
echo ""

log_info "HPAs:"
kubectl get hpa -n "$NAMESPACE"
echo ""

# Get LoadBalancer IPs
log_info "LoadBalancer IPs (may take a moment to assign):"
echo ""
FRONTEND_IP=$(kubectl get svc frontend -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending...")
API_GW_IP=$(kubectl get svc api-gateway -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending...")

echo "  Frontend:    http://$FRONTEND_IP"
echo "  API Gateway: http://$API_GW_IP"
echo ""

echo -e "${BLUE}Next Steps:${NC}"
echo ""
echo "1. Verify deployment:"
echo "   ./tests/verify-deployment.sh $NAMESPACE"
echo ""
echo "2. Run integration tests:"
echo "   ./tests/integration-tests.sh $NAMESPACE"
echo ""
echo "3. Test autoscaling:"
echo "   ./tests/load-testing.sh $NAMESPACE frontend 300"
echo ""
echo "4. Test canary deployment:"
echo "   ./tests/test-canary.sh $NAMESPACE"
echo ""
echo "5. Test blue-green deployment:"
echo "   ./tests/test-blue-green.sh $NAMESPACE status"
echo ""

log_success "Deployment complete!"
