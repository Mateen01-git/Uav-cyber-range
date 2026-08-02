#!/usr/bin/env bash
set -e

N=${1:-2}
CONF_DIR=~/mavlink-bridge-configs
mkdir -p "$CONF_DIR"

# Kill any old routers first
sudo pkill -f mavlink-routerd 2>/dev/null || true

for ((i=0; i<N; i++)); do
    NS="drone$i"
    NS_IP="10.10.0.$((i+10))"
    PX4_PORT=$((14580 + i))
    CONF_FILE="$CONF_DIR/${NS}.conf"

    cat > "$CONF_FILE" <<CONF
[General]
TcpServerPort = 0

[UdpEndpoint px4_local]
Mode = Server
Address = 127.0.0.1
Port = $PX4_PORT

[UdpEndpoint to_namespace]
Mode = Normal
Address = $NS_IP
Port = 14550
CONF

    echo "[+] $NS: Routing PX4 Port $PX4_PORT -> $NS_IP:14550"
    mavlink-routerd -c "$CONF_FILE" >/dev/null 2>&1 &
done

echo "[OK] Host-side MAVLink bridge running silently for $N drones."
