#!/bin/bash

##############################################################################
# E-Commerce Microservices - Cleanup Script
#
# Removes all deployed resources
# Usage: ./cleanup.sh [namespace]
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

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}E-Commerce Application Cleanup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Confirmation
log_warning "This will delete all resources in namespace: $NAMESPACE"
echo ""
read -p "Are you sure? (yes/no): " -r CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log_info "Cleanup cancelled"
    exit 0
fi

echo ""

# Check if Helm release exists
if helm list -n "$NAMESPACE" 2>/dev/null | grep -q ecommerce-app; then
    log_info "Found Helm release, uninstalling..."
    helm uninstall ecommerce-app -n "$NAMESPACE"
    log_success "Helm release uninstalled"
    echo ""
fi

# Delete all resources in namespace
log_info "Deleting all resources in namespace '$NAMESPACE'..."
kubectl delete namespace "$NAMESPACE" --ignore-not-found=true

# Wait for namespace deletion
log_info "Waiting for namespace deletion..."
for i in {1..30}; do
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_success "Namespace '$NAMESPACE' deleted"
        break
    fi
    sleep 1
    echo "  [$i/30] Waiting..."
done

echo ""
log_success "Cleanup completed successfully!"
