#!/bin/bash

# KEDA Deployment Script
# Installs KEDA operator and configures ScaledObjects for event-driven autoscaling

set -e

NAMESPACE="${1:-ecommerce}"
KEDA_NAMESPACE="keda"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/manifests"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}KEDA (Kubernetes Event-Driven Autoscaling) Deployment${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Step 1: Create KEDA namespace and operator
echo -e "${YELLOW}Step 1: Installing KEDA operator...${NC}"
kubectl apply -f "$MANIFESTS_DIR/06-keda-setup.yaml"
echo -e "${GREEN}✓ KEDA operator deployed${NC}"
echo ""

# Step 2: Wait for KEDA operator to be ready
echo -e "${YELLOW}Step 2: Waiting for KEDA operator to be ready...${NC}"
kubectl rollout status deployment/keda-operator -n "$KEDA_NAMESPACE" --timeout=2m || {
  echo -e "${RED}✗ KEDA operator failed to deploy${NC}"
  exit 1
}
echo -e "${GREEN}✓ KEDA operator is ready${NC}"
echo ""

# Step 3: Wait for KEDA metrics server to be ready
echo -e "${YELLOW}Step 3: Waiting for KEDA metrics server to be ready...${NC}"
kubectl rollout status deployment/keda-metrics-apiserver -n "$KEDA_NAMESPACE" --timeout=2m || {
  echo -e "${YELLOW}⚠ KEDA metrics server still starting (this can take a moment)${NC}"
}
echo -e "${GREEN}✓ KEDA metrics server is running${NC}"
echo ""

# Step 4: Apply ScaledObject configurations
echo -e "${YELLOW}Step 4: Configuring ScaledObjects for custom metric-based autoscaling...${NC}"
kubectl apply -f "$MANIFESTS_DIR/07-keda-scalers.yaml"
echo -e "${GREEN}✓ ScaledObjects configured${NC}"
echo ""

# Step 5: Verify ScaledObjects
echo -e "${YELLOW}Step 5: Verifying ScaledObject deployments...${NC}"
SCALED_OBJECTS=$(kubectl get scaledobjects -n "$NAMESPACE" 2>/dev/null || echo "")

if [ -z "$SCALED_OBJECTS" ]; then
  echo -e "${RED}✗ No ScaledObjects found in namespace $NAMESPACE${NC}"
  exit 1
fi

echo -e "${GREEN}✓ ScaledObjects found in namespace $NAMESPACE:${NC}"
kubectl get scaledobjects -n "$NAMESPACE"
echo ""

# Step 6: Display KEDA status
echo -e "${YELLOW}Step 6: KEDA Status:${NC}"
echo ""
echo -e "${BLUE}KEDA Operator Pods:${NC}"
kubectl get pods -n "$KEDA_NAMESPACE" -l app=keda
echo ""

echo -e "${BLUE}ScaledObjects in $NAMESPACE:${NC}"
kubectl get scaledobjects -n "$NAMESPACE" -o wide
echo ""

# Step 7: Display scaling metrics
echo -e "${YELLOW}Step 7: Current Scaling Status:${NC}"
echo ""
for scaler in frontend-scaler api-gateway-scaler product-service-scaler order-service-scaler; do
  echo -e "${BLUE}ScaledObject: $scaler${NC}"
  kubectl describe scaledobject "$scaler" -n "$NAMESPACE" 2>/dev/null | grep -A 5 "Status:\|Conditions:" || echo "  (status not yet available)"
  echo ""
done

echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ KEDA deployment completed successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Ensure Prometheus is installed in your cluster"
echo "2. Configure Prometheus data source in ScaledObjects (update serverAddress)"
echo "3. Monitor scaling behavior: kubectl get hpa -n $NAMESPACE"
echo "4. View KEDA logs: kubectl logs -n $KEDA_NAMESPACE -l app=keda"
echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo "  # View ScaledObjects"
echo "  kubectl get scaledobjects -n $NAMESPACE"
echo ""
echo "  # Describe a ScaledObject"
echo "  kubectl describe scaledobject frontend-scaler -n $NAMESPACE"
echo ""
echo "  # View generated HPA"
echo "  kubectl get hpa -n $NAMESPACE"
echo ""
echo "  # Monitor scaling events"
echo "  kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
echo ""
echo "  # KEDA operator logs"
echo "  kubectl logs -n $KEDA_NAMESPACE -l app=keda -f"
echo ""
