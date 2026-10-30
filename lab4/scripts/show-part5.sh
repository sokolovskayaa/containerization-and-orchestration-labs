#!/usr/bin/env bash
set -euo pipefail
case "${1:-qos}" in
  qos)
    printf 'PART 5: actual pod QoS and priorities\n\n'
    kubectl -n shop get pods -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[*].ready,QOS:.status.qosClass,PRIORITY:.spec.priority,CLASS:.spec.priorityClassName'
    printf '\nResource requests and limits\n\n'
    kubectl -n shop get pods -o custom-columns='NAME:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu,CPU_LIMIT:.spec.containers[*].resources.limits.cpu,MEM_REQ:.spec.containers[*].resources.requests.memory,MEM_LIMIT:.spec.containers[*].resources.limits.memory'
    ;;
  pdb)
    printf 'PART 5: PriorityClass and PodDisruptionBudget\n\n'
    kubectl get priorityclass shop-shop-critical shop-shop-batch
    printf '\n'
    kubectl -n shop get pdb -o wide
    printf '\nPostgreSQL health\n'
    kubectl -n shop get cluster postgres
    printf '\nHelm release\n'
    helm list -n shop
    ;;
  *) exit 2 ;;
esac
