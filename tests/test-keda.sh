#!/bin/bash

# KEDA Scaling Test Script
# Tests event-driven autoscaling with KEDA ScaledObjects

set -e

NAMESPACE="${1:-ecommerce}"
TEST_DURATION="${2:-300}"  # 5 minutes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}KEDA Event-Driven Autoscaling Test${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Test Duration: ${CYAN}$TEST_DURATION seconds${NC}"
echo -e "Namespace: ${CYAN}$NAMESPACE${NC}"
echo ""

# Function to get current replica count
get_replicas() {
  local deployment=$1
  kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0"
}

# Function to get desired replica count from HPA
get_desired_replicas() {
  local hpa=$1
  kubectl get hpa "$hpa" -n "$NAMESPACE" -o jsonpath='{.status.desiredReplicas}' 2>/dev/null || echo "0"
}

# Function to get current metric value
get_metric_value() {
  local scaler=$1
  kubectl describe scaledobject "$scaler" -n "$NAMESPACE" 2>/dev/null | grep -A 5 "Metrics:" | tail -1 || echo "N/A"
}

# Pre-test checks
echo -e "${YELLOW}Pre-Test Checks:${NC}"
echo ""

# Check KEDA operator
if kubectl get pods -n keda -l app=keda &>/dev/null; then
  KEDA_READY=$(kubectl get deployment keda-operator -n keda -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  echo -e "${GREEN}✓ KEDA operator ready (${KEDA_READY} replicas)${NC}"
else
  echo -e "${RED}✗ KEDA operator not found in 'keda' namespace${NC}"
  echo -e "${YELLOW}Run: ./scripts/deploy-keda.sh $NAMESPACE${NC}"
  exit 1
fi

# Check ScaledObjects
SCALED_OBJECTS=$(kubectl get scaledobjects -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$SCALED_OBJECTS" -gt 0 ]; then
  echo -e "${GREEN}✓ Found $SCALED_OBJECTS ScaledObjects${NC}"
else
  echo -e "${RED}✗ No ScaledObjects found${NC}"
  exit 1
fi

# Check deployments
echo -e "${GREEN}✓ Application deployments present${NC}"
echo ""

# Display initial state
echo -e "${YELLOW}Initial State:${NC}"
echo ""
kubectl get deployments -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name,DESIRED:.spec.replicas,CURRENT:.status.replicas,READY:.status.readyReplicas
echo ""

# Display HPA status
echo -e "${YELLOW}Generated HPA Status:${NC}"
echo ""
kubectl get hpa -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name,REFERENCE:.spec.scaleTargetRef.name,TARGETS:.status.currentMetrics[*].type,MINPODS:.spec.minReplicas,MAXPODS:.spec.maxReplicas,REPLICAS:.status.currentReplicas,AGE:.metadata.creationTimestamp
echo ""

# Display ScaledObjects
echo -e "${YELLOW}ScaledObjects Configuration:${NC}"
echo ""
kubectl get scaledobjects -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name,TARGET:.spec.scaleTargetRef.name,MIN:.spec.minReplicaCount,MAX:.spec.maxReplicaCount,TRIGGERS:.spec.triggers[*].type
echo ""

# Test 1: Check metric trigger functionality
echo -e "${YELLOW}Test 1: Metric Trigger Configuration${NC}"
echo ""

for scaler in frontend-scaler api-gateway-scaler product-service-scaler order-service-scaler; do
  echo -e "${CYAN}ScaledObject: $scaler${NC}"
  TRIGGERS=$(kubectl get scaledobject "$scaler" -n "$NAMESPACE" -o jsonpath='{.spec.triggers[*].type}' 2>/dev/null)
  if [ -n "$TRIGGERS" ]; then
    echo -e "  ${GREEN}✓ Triggers configured: ${CYAN}$TRIGGERS${NC}"
  else
    echo -e "  ${RED}✗ No triggers found${NC}"
  fi
done
echo ""

# Test 2: Monitor replica changes during test
echo -e "${YELLOW}Test 2: Monitoring Replica Changes (${TEST_DURATION}s)${NC}"
echo ""

DEPLOYMENTS=("frontend" "api-gateway" "product-service" "order-service")
MONITORING_INTERVAL=10
ELAPSED=0

while [ $ELAPSED -lt $TEST_DURATION ]; do
  echo -e "${CYAN}[$(printf '%03d' $ELAPSED)s]${NC}"

  for deploy in "${DEPLOYMENTS[@]}"; do
    CURRENT=$(get_replicas "$deploy")
    SCALER="${deploy}-scaler"
    HPA="keda-${SCALER}"
    DESIRED=$(get_desired_replicas "$HPA")

    if [ "$CURRENT" == "$DESIRED" ]; then
      echo -e "  ${deploy}: ${GREEN}$CURRENT/$DESIRED replicas${NC}"
    elif [ "$CURRENT" -lt "$DESIRED" ]; then
      echo -e "  ${deploy}: ${YELLOW}$CURRENT/$DESIRED replicas (scaling up...)${NC}"
    else
      echo -e "  ${deploy}: ${YELLOW}$CURRENT/$DESIRED replicas (scaling down...)${NC}"
    fi
  done

  echo ""
  sleep $MONITORING_INTERVAL
  ELAPSED=$((ELAPSED + MONITORING_INTERVAL))
done

# Post-test analysis
echo -e "${YELLOW}Post-Test Analysis:${NC}"
echo ""

# Check final state
echo -e "${CYAN}Final Replica State:${NC}"
kubectl get deployments -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name,DESIRED:.spec.replicas,CURRENT:.status.replicas,READY:.status.readyReplicas
echo ""

# Check HPA conditions
echo -e "${CYAN}HPA Conditions:${NC}"
for scaler in frontend-scaler api-gateway-scaler product-service-scaler order-service-scaler; do
  HPA="keda-${scaler}"
  echo -e "  ${MAGENTA}$HPA:${NC}"
  kubectl get hpa "$HPA" -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name,REFERENCE:.spec.scaleTargetRef.name,MINPODS:.spec.minReplicas,MAXPODS:.spec.maxReplicas,REPLICAS:.status.currentReplicas,MESSAGE:.status.conditions[?(@.type==\"AbleToScale\")].message 2>/dev/null || echo "    (HPA not found)"
done
echo ""

# Check for scaling events
echo -e "${CYAN}Recent Scaling Events:${NC}"
EVENTS=$(kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10)
if [ -n "$EVENTS" ]; then
  echo "$EVENTS" | tail -5
else
  echo "  (No scaling events found)"
fi
echo ""

# Check ScaledObject status
echo -e "${CYAN}ScaledObject Status:${NC}"
for scaler in frontend-scaler api-gateway-scaler product-service-scaler order-service-scaler; do
  STATUS=$(kubectl get scaledobject "$scaler" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null)
  ACTIVE=$(kubectl get scaledobject "$scaler" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Active")].status}' 2>/dev/null)
  if [ "$ACTIVE" == "True" ]; then
    echo -e "  ${GREEN}✓${NC} $scaler: Active"
  else
    echo -e "  ${YELLOW}⚠${NC} $scaler: $ACTIVE"
  fi
done
echo ""

# Test results summary
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ KEDA Scaling Test Completed${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Recommendations
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Generate load to trigger scaling:"
echo "   kubectl run -n $NAMESPACE load-test --image=busybox -i --tty --rm -- /bin/sh"
echo "   while true; do wget -q -O- http://frontend; done"
echo ""
echo "2. Monitor scaling in real-time:"
echo "   kubectl get hpa -n $NAMESPACE --watch"
echo ""
echo "3. View KEDA logs:"
echo "   kubectl logs -n keda -l app=keda -f"
echo ""
echo "4. Check specific ScaledObject details:"
echo "   kubectl describe scaledobject frontend-scaler -n $NAMESPACE"
echo ""

exit 0
