#!/usr/bin/env bash
set -euo pipefail
case "${1:-pending}" in
  pending)
    printf 'PART 6: batch pods waiting for CPU requests\n\n'
    kubectl -n shop get pods -l app=batch -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,CPU_REQUEST:.spec.containers[0].resources.requests.cpu,PRIORITY:.spec.priority,NODE:.spec.nodeName'
    pod="$(kubectl -n shop get pods -l app=batch --field-selector=status.phase=Pending -o jsonpath='{.items[0].metadata.name}')"
    printf '\nScheduler explanation for %s\n\n' "$pod"
    kubectl -n shop get events --field-selector "involvedObject.name=$pod,reason=FailedScheduling" -o custom-columns='REASON:.reason,MESSAGE:.message'
    printf '\nNode allocatable CPU\n'
    kubectl get nodes -o custom-columns='NODE:.metadata.name,CPU:.status.allocatable.cpu'
    ;;
  preemption)
    printf 'PART 6: real scheduler preemption events\n\n'
    kubectl -n shop get events --field-selector=reason=Preempted -o custom-columns='POD:.involvedObject.name,REASON:.reason,MESSAGE:.message'
    printf '\nDeployments after adding high-priority API replicas\n\n'
    kubectl -n shop get deployment api batch
    printf '\nAPI pods whose UIDs appear in the preemption events\n\n'
    python3 - <<'PYCODE'
import json, re, subprocess
pods=json.loads(subprocess.check_output(['kubectl','-n','shop','get','pods','-o','json']))['items']
by_uid={p['metadata']['uid']:p for p in pods}
events=json.loads(subprocess.check_output(['kubectl','-n','shop','get','events','--field-selector=reason=Preempted','-o','json']))['items']
print('API POD                       PRIORITY  CPU REQUEST  NODE')
for event in events:
    match=re.search(r'Preempted by pod ([a-f0-9-]+)',event.get('message',''))
    pod=by_uid.get(match.group(1)) if match else None
    if pod:
        print(pod['metadata']['name'],pod['spec']['priority'],pod['spec']['containers'][0]['resources']['requests']['cpu'],pod['spec']['nodeName'])
PYCODE
    ;;
  restored)
    printf 'PART 6: normal replicas restored after the experiment\n\n'
    kubectl -n shop get pods -o wide
    printf '\n'
    helm list -n shop
    printf '\n'
    kubectl -n shop get cluster postgres
    ;;
  *) exit 2 ;;
esac
