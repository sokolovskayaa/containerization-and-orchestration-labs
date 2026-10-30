#!/usr/bin/env bash
# Build and deploy to the existing lab cluster. Stops on errors.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
mkdir -p lab4/evidence
context="$(kubectl config current-context)"
case "$context" in
  kind-shop) lab4_cluster=shop ;;
  kind-shop-lab4) lab4_cluster=shop-lab4 ;;
  *) echo "Expected kind-shop or kind-shop-lab4; found $context" >&2; exit 1 ;;
esac
kubectl --request-timeout=5s get nodes
docker build --progress=plain -f lab4/services/batch/Dockerfile.standalone -t registry.shop.local/batch:0.1.0 lab4/services/batch 2>&1 | tee lab4/evidence/batch-build.log
kind load docker-image registry.shop.local/batch:0.1.0 --name "$lab4_cluster"
# Keep diagnostics even if rollout times out.
if ! helm upgrade shop lab3/chart/shop -n shop -f lab4/values-part5-final.yaml --wait --timeout 3m; then
  kubectl -n shop get pods -o wide
  kubectl -n shop get events --sort-by=.metadata.creationTimestamp | tail -40
  exit 1
fi
bash lab4/scripts/wait-part5.sh
bash lab4/scripts/capture-evidence.sh part5
kubectl -n shop get pods -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[*].ready,QOS:.status.qosClass,PRIORITY:.spec.priority,CLASS:.spec.priorityClassName'
kubectl -n shop get pdb
