#!/usr/bin/env bash
set -euo pipefail

unshare \
    --pid \
    --mount \
    --net \
    --uts \
    --ipc \
    --user \
    --fork \
    -r \
    bash -c '
        mount -t proc proc /proc
        ip link set lo up

        echo "Container started"
        sleep infinity
    ' &

PID=$!

echo "Container PID: $PID"

# Создаём veth-пару в host network namespace.
sudo ip link add veth-host type veth peer name veth-cont

# Переносим один конец в network namespace контейнера.
sudo ip link set veth-cont netns "$PID"

# Настраиваем host.
sudo ip addr add 10.0.0.1/24 dev veth-host
sudo ip link set veth-host up

# Настраиваем container.
sudo nsenter -t "$PID" -n \
    ip addr add 10.0.0.2/24 dev veth-cont

sudo nsenter -t "$PID" -n \
    ip link set veth-cont up

sudo nsenter -t "$PID" -n \
    .venv/bin/flask --app main run --host=0.0.0.0

sudo ip link delete veth-host