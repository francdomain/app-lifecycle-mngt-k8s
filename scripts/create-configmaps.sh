#!/bin/bash

##############################################################################
# Create ConfigMaps from separate configuration files
# This script creates ConfigMaps using kubectl's --from-file feature
# Usage: ./create-configmaps.sh [namespace]
##############################################################################

set -e

NAMESPACE=${1:-ecommerce}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Project root (one level up from scripts)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

echo -e "${BLUE}Creating ConfigMaps from configuration files...${NC}"
echo ""

# Create namespace if it doesn't exist
log_info "Ensuring namespace '$NAMESPACE' exists..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
log_success "Namespace ready"
echo ""

# Create API Gateway ConfigMap from nginx.conf (manifests directory)
log_info "Creating api-gateway-config ConfigMap from manifests/api-gateway/nginx.conf..."
kubectl create configmap api-gateway-config \
  --from-file="$PROJECT_ROOT/manifests/api-gateway/nginx.conf" \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -
log_success "api-gateway-config created"
echo ""

# Create Frontend Nginx ConfigMap (for /health and static serving)
log_info "Creating frontend-config ConfigMap from manifests/frontend/nginx.conf..."
kubectl create configmap frontend-config \
  --from-file="$PROJECT_ROOT/manifests/frontend/nginx.conf" \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -
log_success "frontend-config created"
echo ""

# Create Frontend ConfigMap from index.html (manifests directory)
log_info "Creating frontend-html ConfigMap from manifests/frontend/index.html..."
kubectl create configmap frontend-html \
  --from-file="$PROJECT_ROOT/manifests/frontend/index.html" \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -
log_success "frontend-html created"
echo ""

# Verify ConfigMaps
log_info "Verifying ConfigMaps..."
echo ""

log_info "API Gateway ConfigMap:"
kubectl get configmap api-gateway-config -n "$NAMESPACE" -o jsonpath='{.data}' | jq . 2>/dev/null || kubectl get configmap api-gateway-config -n "$NAMESPACE"
echo ""

log_info "Frontend ConfigMap:"
kubectl get configmap frontend-html -n "$NAMESPACE" -o jsonpath='{.data.index\.html}' | head -20
echo "... (truncated for brevity)"
echo ""

log_success "All ConfigMaps created successfully!"
