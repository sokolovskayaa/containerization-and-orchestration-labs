#!/bin/sh

URL="http://shop-api.shop.svc.cluster.local:80/orders"

echo "timestamp,status"

i=0
while [ "$i" -lt 500 ]; do
    timestamp=$(date -u +%s)

    if status=$(curl --noproxy '*' \
        -s -o /dev/null \
        -w '%{http_code}' \
        --connect-timeout 1 \
        --max-time 3 \
        -X POST "$URL"); then
        :
    else
        status=000
    fi

    echo "$timestamp,$status"

    i=$((i + 1))
    sleep 0.25
done