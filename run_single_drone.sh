#!/usr/bin/env bash
# 1. Clean background processes & restore terminal formatting
sudo pkill -9 -f gz 2>/dev/null || true
sudo pkill -9 -f px4 2>/dev/null || true
sudo pkill -9 -f ruby 2>/dev/null || true
stty sane

# 2. Environment Variables
export LIBGL_ALWAYS_SOFTWARE=1
export GZ_SIM_RESOURCE_PATH=$HOME/PX4-Autopilot/Tools/simulation/gz/models:$HOME/PX4-Autopilot/Tools/simulation/gz/worlds
export PX4_GZ_STANDALONE=1

echo "[*] Launching Gazebo 3D Visual Engine..."
gz sim -r $HOME/PX4-Autopilot/Tools/simulation/gz/worlds/default.sdf >/dev/null 2>&1 &

# 3. Wait for Gazebo render tree to settle
sleep 3

echo "[*] Launching PX4 Flight Controller..."
cd ~/PX4-Autopilot
make px4_sitl gz_x500
