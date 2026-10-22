#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="shop"
COUNT="${1:-12}"

echo "timestamp,role,pod,ip" > evidence/chaos.csv

for ((i=1; i<=COUNT; i++)); do
    if (( RANDOM % 2 == 0 )); then
        role="api"
    else
        role="worker"
    fi

    deployment="shop-$role"

    mapfile -t ready < <(
        kubectl get pods \
            -n "$NAMESPACE" \
            -l "app=$role" \
            --no-headers |
        awk '$2 == "1/1" && $3 == "Running" {print $1}'
    )

    desired=$(kubectl get deployment "$deployment" \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.replicas}')

    if (( ${#ready[@]} < desired )); then
        echo "Skipping $role: replicas not ready" >&2
        sleep 4
        continue
    fi

    victim=$(printf '%s\n' "${ready[@]}" | shuf -n 1)

    ip=$(kubectl get pod "$victim" \
        -n "$NAMESPACE" \
        -o jsonpath='{.status.podIP}')

    timestamp=$(date -u +%s)

    echo "$timestamp,$role,$victim,$ip" \
        >> evidence/chaos.csv

    echo "Deleting $victim ($ip)" >&2

    kubectl delete pod "$victim" \
        -n "$NAMESPACE" \
        --wait=false >/dev/null

    kubectl rollout status \
        "deployment/$deployment" \
        -n "$NAMESPACE" \
        --timeout=90s >/dev/null

    sleep 6
done

echo "Chaos experiment completed" >&2