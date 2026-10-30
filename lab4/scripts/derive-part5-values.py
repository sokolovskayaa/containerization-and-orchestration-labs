"""Generate Helm resources from recorded KRR results; never invent missing values."""
import json
import math
from pathlib import Path

root = Path(__file__).resolve().parents[1]
values = {'protection': {'enabled': True}, 'batch': {'enabled': True, 'replicas': 1},
          'api': {'replicas': 3}}
for filename, names in [('deployments-final.json', ['api', 'worker']),
                        ('postgres-final.json', ['postgres'])]:
    scans = {row['object']['name']: row for row in json.loads(
        (root/'evidence/krr'/filename).read_text())['scans']}
    for name in names:
        recommendation = scans[name]['recommended']['requests']
        cpu, memory = recommendation['cpu']['value'], recommendation['memory']['value']
        if not isinstance(cpu, (int, float)) or not isinstance(memory, (int, float)):
            raise SystemExit(f'Missing numeric recommendation for {name}')
        if cpu <= 0 or memory <= 0:
            raise SystemExit(f'Invalid recommendation for {name}')
        request = {'cpu': f'{math.ceil(cpu * 1000)}m', 'memory': f'{math.ceil(memory/1048576)}Mi'}
        limit = dict(request)
        if name == 'worker':
            limit['cpu'] = f'{max(250, math.ceil(cpu * 1000))}m'
        values.setdefault(name, {})['resources'] = {'requests': request, 'limits': limit}
# JSON is a YAML subset: this avoids an extra PyYAML dependency.
(root/'values-part5-final.yaml').write_text(
    '# Generated from deployments-final.json and postgres-final.json in evidence/krr/.\n'
    '# CPU floors: API/worker 100m; PostgreSQL 250m. CPU limits retained for lab guardrails.\n'
    + json.dumps(values, indent=2) + '\n')
