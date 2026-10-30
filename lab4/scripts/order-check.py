"""Short supplementary order check from a pod; standard library only."""
import concurrent.futures
import json
import os
import time
import urllib.error
import urllib.request

url = os.environ.get('ORDER_URL', 'http://api.shop.svc.cluster.local/order')
count = int(os.environ.get('ORDER_COUNT', '150'))
rate = float(os.environ.get('ORDER_RATE', '5'))

def order(_):
    started = time.perf_counter()
    try:
        req = urllib.request.Request(url, data=b'{"item":"part5-service-check","quantity":1}',
                                     headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(req, timeout=5) as response:
            status = response.status
            response.read()
        error = None
    except urllib.error.HTTPError as exc:
        status, error = exc.code, str(exc)
    except Exception as exc:
        status, error = 0, str(exc)
    return {'status': status, 'duration_ms': (time.perf_counter()-started)*1000, 'error': error}

start = time.perf_counter()
with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
    tasks = []
    for i in range(count):
        time.sleep(max(0, start + i/rate - time.perf_counter()))
        tasks.append(executor.submit(order, i))
    results = [t.result() for t in tasks]
latencies = sorted(r['duration_ms'] for r in results if r['status'] == 201)
success = len(latencies)
report = {'target': url, 'requests': count, 'success_201': success,
          'failed': count-success, 'elapsed_seconds': time.perf_counter()-start,
          'rate_target': rate, 'p95_success_ms': latencies[max(0, int(len(latencies)*0.95+0.999)-1)] if latencies else None,
          'errors': [r for r in results if r['status'] != 201]}
print(json.dumps(report, indent=2))
raise SystemExit(0 if success == count else 1)
