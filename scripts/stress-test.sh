#!/usr/bin/env bash
# Quick HPA stress test: ensure metrics-server and HPA are in place, then run
# load for 90s so pods scale up. In other terminals run the watch commands below.
# See documents/STRESS-TEST.md for full steps (including metrics-server install).

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== Checking metrics-server ==="
if ! kubectl get deployment metrics-server -n kube-system &>/dev/null; then
  echo "metrics-server not found. Install it first:"
  echo "  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
  echo "See documents/STRESS-TEST.md for Docker Desktop TLS note."
  exit 1
fi
echo "metrics-server OK"

echo ""
echo "=== Applying HPA ==="
kubectl apply -f k8s/hpa.yaml
echo ""

echo "In two other terminals, run:"
echo "  Terminal 1: kubectl get pods -n news-sentiment -w"
echo "  Terminal 2: kubectl get hpa -n news-sentiment -w"
echo ""
echo "=== Running load for 90s (30 concurrent) ==="
kubectl run -it --rm hey --image=williamyeh/hey --restart=Never -n news-sentiment -- \
  hey -z 90s -c 30 http://news-sentiment-api-service/api/v1/today
