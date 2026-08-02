#!/usr/bin/env bash
echo "[*] Stopping everything..."
~/swarm-mesh/teardown_swarm_mesh.sh 4 2>/dev/null || true
sudo pkill -f mavlink-routerd 2>/dev/null || true
sudo pkill -9 -f px4 2>/dev/null || true
sudo pkill -9 -f gz 2>/dev/null || true
tmux kill-server 2>/dev/null || true
echo "[OK] All processes killed and network cleaned up!"
