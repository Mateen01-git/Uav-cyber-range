#!/usr/bin/env bash
set -e
N=${1:-2}

CONF_DIR=~/mavlink-router-configs
mkdir -p "$CONF_DIR"

sudo pkill -f mavlink-routerd 2>/dev/null || true

for i in $(seq 0 $((N-1))); do
    NS="drone$i"
    VETH_N="veth${i}n"

    IP=$(sudo ip netns exec "$NS" ip -4 addr show "$VETH_N" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [[ -z "$IP" ]]; then
        continue
    fi

    # LISTEN_PORT starts at 14560 (14560 for drone0, 14561 for drone1...)
    LISTEN_PORT=$((14560 + i))
    CONF_FILE="$CONF_DIR/${NS}.conf"

    cat > "$CONF_FILE" <<CONF
[General]
TcpServerPort = 0

[UdpEndpoint rx_from_px4]
Mode = Normal
Address = $IP
Port = $LISTEN_PORT

[UdpEndpoint forward_to_qgc]
Mode = Normal
Address = 10.10.0.1
Port = 14550
CONF

    echo "[+] Router $NS: Listening on $IP:$LISTEN_PORT -> Forwarding to Host QGC (10.10.0.1:14550)"
    sudo ip netns exec "$NS" mavlink-routerd -c "$CONF_FILE" >/dev/null 2>&1 &
done

echo "[OK] MAVLink Routers configured with clean QGC separation."
