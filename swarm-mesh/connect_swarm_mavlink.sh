#!/usr/bin/env bash
N=${1:-2}

echo "[*] Connecting PX4 instances to Drone Router Endpoints..."

for ((i=0; i<N; i++)); do
    SESSION="px4_${i}"
    TARGET_IP="10.10.0.$((10 + i))"
    TARGET_PORT="$((14560 + i))"

    tmux send-keys -t "$SESSION" "mavlink start -u $((14570 + i)) -o $TARGET_PORT -r 1000000 -t $TARGET_IP" C-m
    echo "[+] Linked $SESSION -> $TARGET_IP:$TARGET_PORT"
done

echo "[OK] All MAVLink streams connected."
