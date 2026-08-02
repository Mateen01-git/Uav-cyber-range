#!/usr/bin/env bash
# Dynamic drone network builder — no batman-adv required.
set -e

N=${1:-3}
USE_DHCP=false
[[ "$2" == "--dhcp" ]] && USE_DHCP=true

BRIDGE="br-mesh"
SUBNET_BASE="10.10.0"
DHCP_RANGE_START="10.10.0.50"
DHCP_RANGE_END="10.10.0.200"

echo "[*] Building dynamic drone network for $N drones (DHCP mode: $USE_DHCP)"

if ! ip link show "$BRIDGE" &>/dev/null; then
    sudo ip link add name "$BRIDGE" type bridge
    sudo ip link set "$BRIDGE" up
    echo "[+] Created bridge $BRIDGE"
fi

if $USE_DHCP; then
    sudo ip addr add "${SUBNET_BASE}.1/24" dev "$BRIDGE" 2>/dev/null || true
fi

for i in $(seq 0 $((N-1))); do
    NS="drone$i"
    VETH_H="veth${i}h"
    VETH_N="veth${i}n"

    echo "[*] Setting up $NS..."
    sudo ip netns add "$NS" 2>/dev/null || echo "    (namespace $NS already exists, reusing)"

    if ! sudo ip netns exec "$NS" ip link show "$VETH_N" &>/dev/null; then
        sudo ip link add "$VETH_H" type veth peer name "$VETH_N"
        sudo ip link set "$VETH_N" netns "$NS"
        sudo ip link set "$VETH_H" master "$BRIDGE"
        sudo ip link set "$VETH_H" up
    fi

    sudo ip netns exec "$NS" ip link set lo up
    sudo ip netns exec "$NS" ip link set "$VETH_N" up

    if $USE_DHCP; then
        echo "    [DHCP] requesting lease for $NS..."
        sudo ip netns exec "$NS" udhcpc -i "$VETH_N" -q -n &
    else
        IP="${SUBNET_BASE}.$((i+10))/24"
        sudo ip netns exec "$NS" ip addr flush dev "$VETH_N"
        sudo ip netns exec "$NS" ip addr add "$IP" dev "$VETH_N"
        echo "    [+] $NS -> $VETH_N = $IP"
    fi
done

if $USE_DHCP; then
    echo "[*] Starting dnsmasq DHCP server on $BRIDGE..."
    sudo pkill -f "dnsmasq.*$BRIDGE" 2>/dev/null || true
    sudo dnsmasq --interface="$BRIDGE" --bind-interfaces \
        --dhcp-range="${DHCP_RANGE_START},${DHCP_RANGE_END},12h" \
        --except-interface=lo \
        --pid-file=/tmp/dnsmasq-mesh.pid
    sleep 2
fi

echo
echo "[OK] Drone network ready for $N drones."
echo "    Check IP: sudo ip netns exec drone0 ip -4 addr show"
echo "    Test:     sudo ip netns exec drone0 ping -c 3 <drone1's IP>"
