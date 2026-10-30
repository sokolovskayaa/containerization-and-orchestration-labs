#!/usr/bin/env bash
set -euo pipefail
kubectl -n shop rollout status deployment/api --timeout=180s
kubectl -n shop rollout status deployment/batch --timeout=180s
kubectl -n shop rollout status deployment/worker --timeout=180s
# Helm --wait does not wait for a CNPG custom resource to finish its rollout.
python3 - <<'PY'
import json, subprocess, time

def get(kind, name):
    return json.loads(subprocess.check_output(
        ['kubectl','--request-timeout=5s','-n','shop','get',kind,name,'-o','json'],
        stderr=subprocess.DEVNULL))

end=time.monotonic()+180
stable=0
while time.monotonic()<end:
    try:
        cluster=get('cluster','postgres')
        pod=get('pod','postgres-1')
        resource=next(c['resources'] for c in pod['spec']['containers'] if c['name']=='postgres')
        healthy=(cluster.get('status',{}).get('phase')=='Cluster in healthy state'
                 and not pod['metadata'].get('deletionTimestamp')
                 and all(c['ready'] for c in pod['status']['containerStatuses'])
                 and resource==cluster['spec']['resources'])
    except (subprocess.SubprocessError, KeyError, StopIteration):
        healthy=False
    stable=stable+1 if healthy else 0
    if stable>=3:
        print('PostgreSQL healthy; live resources match desired resources; readiness stable')
        break
    time.sleep(2)
else:
    raise SystemExit('PostgreSQL did not reach a stable desired state within 180 seconds')
PY
