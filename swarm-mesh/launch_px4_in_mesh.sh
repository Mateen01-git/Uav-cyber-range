#!/usr/bin/env bash
# Launches Gazebo + N PX4 SITL instances, each inside its own drone namespace.
# Mirrors the working logic of launch_swarm.sh (gz sim standalone + env vars),
# just with each PX4 process run inside its droneN namespace.
#
# Usage: ./launch_px4_in_mesh.sh <NUM_DRONES>
# Run setup_dynamic_swarm_mesh.sh FIRST.

set -e

N=${1:-3}
SPACING=2
PX4_DIR=~/PX4-Autopilot
BOOT_WAIT=6

echo ">>> Cleaning up old sessions..."
sudo pkill -9 -f gz 2>/dev/null || true
sudo pkill -9 -f px4 2>/dev/null || true
tmux kill-server 2>/dev/null || true
sleep 2

echo ">>> Starting Gazebo (host network, unchanged)..."
gz sim -r default.sdf &
sleep 15

cd "$PX4_DIR"

for ((i=0; i<N; i++)); do
    X=$((i * SPACING))
    NS="drone$i"
    SESSION="px4_${i}"

    echo ">>> Launching $NS at pose ($X,0) in tmux session '$SESSION' (inside namespace)..."
    sudo ip netns exec "$NS" tmux new-session -d -s "$SESSION" \
        "PX4_SIM_MODEL=gz_x500 PX4_GZ_STANDALONE=1 PX4_GZ_MODEL_POSE='${X},0' sudo ip netns exec $NS $PX4_DIR/build/px4_sitl_default/bin/px4 -i ${i}"

    sleep "$BOOT_WAIT"
done

echo ""
echo ">>> All $N drone(s) launched inside their namespaces."
echo "Attach to a drone's console with:  sudo ip netns exec drone0 tmux attach -t px4_0"
