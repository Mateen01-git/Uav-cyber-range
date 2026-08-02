#!/usr/bin/env bash
N=${1:-3}
BRIDGE="br-mesh"

echo "[*] Stopping mavlink-routerd instances..."
sudo pkill -f mavlink-routerd 2>/dev/null || true

echo "[*] Stopping PX4 instances..."
sudo pkill -f px4_sitl_default/bin/px4 2>/dev/null || true

echo "[*] Stopping dnsmasq (if running)..."
sudo pkill -f "dnsmasq.*$BRIDGE" 2>/dev/null || true

echo "[*] Removing drone namespaces..."
for i in $(seq 0 $((N-1))); do
    sudo ip netns del "drone$i" 2>/dev/null && echo "    removed drone$i" || true
done

echo "[*] Removing bridge $BRIDGE..."
sudo ip link del "$BRIDGE" 2>/dev/null || true

echo "[OK] Teardown complete."
