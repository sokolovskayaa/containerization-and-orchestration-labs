#!/usr/bin/env bash
# Read-only snapshot. Run from any directory with access to the lab cluster.
set -euo pipefail
stage="${1:?Usage: capture-evidence.sh part5|part6-pending|part6-preemption}"
case "$stage" in part5|part6-pending|part6-preemption) ;; *) exit 2 ;; esac
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/evidence/$stage-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out"
kubectl --request-timeout=5s get nodes -o wide > "$out/nodes.txt" 2>&1
kubectl -n shop get pods -o wide > "$out/pods.txt"
kubectl -n shop get pods -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,QOS:.status.qosClass,PRIORITY:.spec.priority,CLASS:.spec.priorityClassName,NOMINATED:.status.nominatedNodeName,NODE:.spec.nodeName' > "$out/qos-priority.txt"
kubectl -n shop get pdb -o wide > "$out/pdb.txt"
kubectl -n shop describe pods > "$out/describe-pods.txt"
kubectl -n shop get events --sort-by=.metadata.creationTimestamp > "$out/events.txt"
kubectl -n shop get pods -o yaml > "$out/pods.yaml"
helm get values shop -n shop -a > "$out/helm-values.yaml"
printf 'Evidence saved: %s\n' "$out"
