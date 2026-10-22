#!/usr/bin/env bash
set -euo pipefail

mkdir -p evidence

FAULT_FILE="evidence/.fault-values.yaml"
ANSWER_FILE="evidence/.fault-answer.txt"

# Случайный выбор одной из четырёх неисправностей.
case $((RANDOM % 4)) in

  0)
    FAULT="wrong-api-label"
    cat > "$FAULT_FILE" <<'EOF'
networkPolicy:
  selectors:
    api:
      app: api-broken
EOF
    ;;

  1)
    FAULT="wrong-postgres-label"
    cat > "$FAULT_FILE" <<'EOF'
networkPolicy:
  selectors:
    postgres:
      cnpg.io/cluster: wrong-postgres
EOF
    ;;

  2)
    FAULT="wrong-postgres-port"
    cat > "$FAULT_FILE" <<'EOF'
networkPolicy:
  ports:
    postgres: 15432
EOF
    ;;

  3)
    FAULT="wrong-dns-port"
    cat > "$FAULT_FILE" <<'EOF'
networkPolicy:
  dns:
    port: 5353
EOF
    ;;

esac

# Ответ сохраняем отдельно, но не показываем.
echo "$FAULT" > "$ANSWER_FILE"

helm upgrade shop ./helm/shop \
  -n shop \
  -f helm/shop/values.yaml \
  -f "$FAULT_FILE" \
  > evidence/fault-helm.log

# Создаём новые Pod, чтобы исключить влияние
# уже установленных соединений с PostgreSQL.
kubectl rollout restart \
  deployment/shop-api \
  deployment/shop-worker \
  -n shop > /dev/null

echo "One network failure has been injected."
echo "Investigate the issue using Hubble."