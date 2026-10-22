#!/usr/bin/env bash
set -euo pipefail

NS=shop
DEBUG="audit-$(date +%s)"
IMAGE="nicolaka/netshoot:latest"

mkdir -p evidence
CSV="evidence/access-matrix.csv"

# Выбираем работающие Pod приложения.
mapfile -t APIS < <(
  kubectl get pods -n "$NS" -l app=api \
    --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
)

API="${APIS[0]}"
OTHER_API="${APIS[1]}"

WORKER=$(kubectl get pods -n "$NS" -l app=worker \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')

POSTGRES=$(kubectl get pods -n "$NS" \
  -l cnpg.io/cluster=shop-postgres \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')

API_IP=$(kubectl get pod "$API" -n "$NS" \
  -o jsonpath='{.status.podIP}')

OTHER_API_IP=$(kubectl get pod "$OTHER_API" -n "$NS" \
  -o jsonpath='{.status.podIP}')

PG_IP=$(kubectl get pod "$POSTGRES" -n "$NS" \
  -o jsonpath='{.status.podIP}')

# Создаём два тестовых Pod.
kubectl delete pod -n "$NS" \
  matrix-client outsider \
  --ignore-not-found >/dev/null

kubectl run matrix-client -n "$NS" \
  --image="$IMAGE" \
  --labels=run=load-client \
  --restart=Never \
  --command -- sleep 1800

kubectl run outsider -n "$NS" \
  --image="$IMAGE" \
  --labels=run=outsider \
  --restart=Never \
  --command -- sleep 1800

kubectl wait -n "$NS" \
  --for=condition=Ready \
  pod/matrix-client pod/outsider \
  --timeout=180s

# Добавляем инструменты диагностики в существующие Pod.
add_debug() {
  local pod="$1"
  local target
  target=$(kubectl get pod "$pod" -n "$NS" \
    -o jsonpath='{.spec.containers[0].name}')

  kubectl debug -n "$NS" "pod/$pod" \
    --image="$IMAGE" \
    --container="$DEBUG" \
    --target="$target" \
    --profile=general \
    -- sleep 1800 >/dev/null

  # Ожидаем готовности отладочного контейнера.
  for i in $(seq 1 60); do
    if kubectl exec -n "$NS" "$pod" \
      -c "$DEBUG" -- true >/dev/null 2>&1; then
      return
    fi
    sleep 2
  done

  echo "Debug container failed: $pod" >&2
  exit 1
}

add_debug "$API"
add_debug "$WORKER"
add_debug "$POSTGRES"

# Определяем Pod и контейнер для каждого источника.
set_source() {
  case "$1" in
    client)   POD=matrix-client; CONTAINER=matrix-client ;;
    outsider) POD=outsider; CONTAINER=outsider ;;
    api)      POD="$API"; CONTAINER="$DEBUG" ;;
    worker)   POD="$WORKER"; CONTAINER="$DEBUG" ;;
    postgres) POD="$POSTGRES"; CONTAINER="$DEBUG" ;;
  esac
}

# Проверяем DNS до сетевой матрицы.
for source in client outsider api worker postgres; do
  set_source "$source"

  if ! kubectl exec -n "$NS" "$POD" \
      -c "$CONTAINER" -- \
      dig +short +tries=1 +time=2 \
      shop-api.shop.svc.cluster.local |
      grep -Eq '^[0-9]+\.'; then
    echo "DNS FAILED: $source" >&2
    exit 1
  fi

  echo "DNS OK: $source"
done

echo "source,destination,expected,observed,result" > "$CSV"

check() {
  local source="$1"
  local dest="$2"
  local port="$3"
  local expected="$4"

  set_source "$source"

  local observed="deny"

  if kubectl exec -n "$NS" "$POD" \
      -c "$CONTAINER" -- \
      nc -z -w 3 "$dest" "$port" \
      >/dev/null 2>&1; then
    observed="allow"
  fi

  local result="FAIL"
  [[ "$observed" == "$expected" ]] && result="PASS"

  printf '%s,%s:%s,%s,%s,%s\n' \
    "$source" "$dest" "$port" \
    "$expected" "$observed" "$result" |
    tee -a "$CSV"
}

# Разрешённые маршруты.
check client shop-api.shop.svc.cluster.local 80 allow
check api shop-postgres-rw.shop.svc.cluster.local 5432 allow
check worker shop-postgres-rw.shop.svc.cluster.local 5432 allow

# Запрещённые маршруты.
check client "$PG_IP" 5432 deny
check outsider "$PG_IP" 5432 deny
check outsider "$API_IP" 8080 deny
check worker "$API_IP" 8080 deny
check api "$OTHER_API_IP" 8080 deny
check postgres "$API_IP" 8080 deny

echo
echo "Results:"
awk -F, '
  NR > 1 {
    total++
    if ($5 == "PASS") passed++
  }
  END {
    printf "%d/%d checks passed\n", passed, total
  }
' "$CSV"