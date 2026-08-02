# Multi-UAV Simulation Framework (PX4 SITL + Gazebo + MAVLink)

A simulation environment for both a **single simulated drone** and a **multi-drone swarm**, built on **PX4 Autopilot (v1.15.4)**, **Gazebo Sim**, **QGroundControl**, and **MAVLink**. The swarm mode adds Linux network namespaces and `mavlink-router` so each drone behaves like an isolated, independent vehicle instead of sharing one internal network.

Tested on Ubuntu 22.04 / 24.04, native or inside WSL2 (Windows 10/11).

---

## Repository Contents

```
.
├── README.md                          # This file
├── mavlink_common.lua                 # Wireshark MAVLink dissector
├── run_single_drone.sh                # One-command single-drone launcher
└── swarm-mesh/                        # Multi-drone swarm network system
    ├── setup_dynamic_swarm_mesh.sh    # Creates bridge + isolated namespaces + IPs
    ├── launch_px4_in_mesh.sh          # Launches Gazebo + PX4 instances inside namespaces
    ├── launch_mavlink_routers.sh      # Starts mavlink-routerd per drone, forwards to QGC
    ├── mavlink_bridge_host.sh         # Alternate host-side bridge (port-forward variant)
    ├── connect_swarm_mavlink.sh       # Points each PX4 tmux session at its router
    ├── check_mavlink_router.sh        # Diagnostics: is mavlink-router installed/running?
    ├── teardown_swarm_mesh.sh         # Removes namespaces + bridge
    └── stop_all.sh                    # Kills everything and tears down the network
```

---

## 1. Basic Requirements

- Ubuntu 22.04 or 24.04 (native install or WSL2 on Windows 10/11 — both work)
- 16GB RAM minimum
- Internet connection for the install scripts

---

## 2. Install Gazebo + PX4

```bash
cd ~
git clone https://github.com/PX4/PX4-Autopilot.git --recursive
cd PX4-Autopilot
git checkout v1.15.4
bash ./Tools/setup/ubuntu.sh
```

This single script installs both Gazebo and all PX4 build dependencies.

Reboot after it finishes:

```bash
sudo reboot
```

Build PX4 with the Gazebo simulator target once, so it's ready to launch:

```bash
cd ~/PX4-Autopilot
make px4_sitl gz_x500
```

Let it fully build. Once you see the simulator open and the `pxh>` prompt, it worked — close it with `Ctrl+C`.

---

## 3. Install QGroundControl (Ubuntu)

```bash
sudo usermod -aG dialout $USER
sudo apt-get remove modemmanager -y
sudo apt install gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-gl -y
sudo apt install libfuse2 -y
sudo apt install libxcb-xinerama0 libxkbcommon-x11-0 libxcb-cursor0 -y
```

Log out and back in (for the `dialout` group to apply). Then download QGC:

```bash
cd ~
wget https://d176tv9ibo4jno.cloudfront.net/latest/QGroundControl.AppImage
chmod +x ./QGroundControl.AppImage
```

Run it:

```bash
./QGroundControl.AppImage
```

---

## 4. Mode 1 — Single Drone

### Option A: Manual (two terminals)

**Terminal 1 — Gazebo + PX4:**
```bash
cd ~/PX4-Autopilot
make px4_sitl gz_x500
```

**Terminal 2 — QGroundControl:**
```bash
cd ~
./QGroundControl.AppImage
```

QGC auto-connects to PX4 over UDP. You should see the drone appear with telemetry, and can arm/takeoff/land directly from QGC.

### Option B: One-command launcher (recommended on WSL2)

If Gazebo hangs or the terminal output gets scrambled on WSL2, use the included launcher, which forces software rendering, runs Gazebo un-paused, and waits for it to settle before starting PX4:

```bash
./run_single_drone.sh
```

Then open QGroundControl. If it doesn't auto-connect:
`QGC icon (top-left) → Application Settings → Comm Links → Add`
- Type: `UDP`
- Port: `14550`
- Check **Server Mode**
- Click **OK**, select it, click **Connect**

---

## 5. Mode 2 — Multi-Drone Swarm

**Why:** Running several PX4 instances directly on the host means they all share the same internal network — not realistic for testing real swarm communication or network-level attacks. The `swarm-mesh/` scripts give each simulated drone its own isolated Linux network namespace with its own virtual network interface and IP, connected through a virtual bridge (`br-mesh`) — similar to how physically separate drones would talk to each other over radio.

| Node | Namespace | Interface | Static IP | MAVLink Port | Forwards To |
|---|---|---|---|---|---|
| Host / QGC | *(host)* | `br-mesh` | `10.10.0.1` | `14550` | — |
| Drone 0 | `drone0` | `veth0n` | `10.10.0.10/24` | `14560` | `10.10.0.1:14550` |
| Drone 1 | `drone1` | `veth1n` | `10.10.0.11/24` | `14561` | `10.10.0.1:14550` |
| Drone N | `droneN` | `vethNn` | `10.10.0.1(N+10)/24` | `1456N` | `10.10.0.1:14550` |

### Step-by-step execution (N = number of drones, e.g. 2)

```bash
# 1. Build the virtual mesh network (bridge + namespaces + IPs)
cd ~/swarm-mesh
./setup_dynamic_swarm_mesh.sh 2
sudo ip addr add 10.10.0.1/24 dev br-mesh 2>/dev/null || true

# 2. Launch Gazebo + PX4 SITL instances, each inside its own namespace
./launch_px4_in_mesh.sh 2
# Wait ~15-20 seconds for PX4 to finish booting inside tmux

# 3. Start the MAVLink routers (one per drone namespace)
./launch_mavlink_routers.sh 2

# 4. Point each PX4 instance's telemetry stream at its router
./connect_swarm_mavlink.sh 2

# 5. Launch QGroundControl
./QGroundControl.AppImage
```

QGroundControl listens on `10.10.0.1:14550` and will show one vehicle icon per drone (SysID 1, 2, 3…), each fed by its own isolated namespace and router.

### Verifying drones are actually talking

```bash
# Ping Drone 1 from Drone 0's namespace
sudo ip netns exec drone0 ping 10.10.0.11 -c 4

# Watch live MAVLink packets arriving on Drone 1's interface
sudo ip netns exec drone1 tcpdump -i veth1n udp port 14561 -c 5
```

### Diagnostics

```bash
cd ~/swarm-mesh
./check_mavlink_router.sh
```

### Stopping / cleaning up

```bash
# Kill every process and remove the virtual network cleanly
~/swarm-mesh/stop_all.sh

# Or just tear down the network namespaces/bridge (leaves processes running)
~/swarm-mesh/teardown_swarm_mesh.sh 2
```

> **Note:** Single-drone mode (`run_single_drone.sh`) and swarm mode (`swarm-mesh/`) don't interfere with each other — running one doesn't break the other's scripts or configuration.

---

## 6. MAVLink Packet Capture (Wireshark)

**Key fact:** if running inside WSL2, PX4↔QGC loopback traffic goes through an interface named `loopback0`, not `lo`. Capturing on `lo` will show 0 packets. On native Ubuntu, capture on `lo` as normal. For swarm mode, capture on the individual `vethNn` interface inside the relevant namespace, or on `br-mesh` to see all mesh traffic.

Install the dissector (`mavlink_common.lua`, included in this repo):

```bash
mkdir -p ~/.local/lib/wireshark/plugins
cp mavlink_common.lua ~/.local/lib/wireshark/plugins/
```

Launch Wireshark from the terminal (not a separate GUI shortcut, so it inherits your environment variables):

```bash
wireshark
```

- **Interface:** `loopback0` (WSL2, single drone) · `lo` (native Ubuntu, single drone) · `br-mesh` or a specific `vethNn` inside a namespace (swarm mode — use `sudo ip netns exec droneN wireshark` or capture with `tcpdump` as shown above)
- **Filter:** `mavlink_proto` or `udp.port == 14550`

---

## 7. Common Compatibility Issues

| Issue | Fix |
|---|---|
| PX4 falls back to internal simulator instead of Gazebo, log shows "No autostart ID found" | Make sure you built with `make px4_sitl gz_x500` exactly — not `make px4_sitl` alone |
| `ERROR [gz_bridge] Service call timed out` | Gazebo froze on WSL2 graphics init. Kill stray processes (`sudo pkill -9 -f gz`), then use `run_single_drone.sh`, which forces `LIBGL_ALWAYS_SOFTWARE=1` and runs Gazebo un-paused before PX4 attaches |
| Gazebo window opens but is blank / drone not visible | Simulation is paused. Click the **Play ▶** button in Gazebo, or launch Gazebo with `gz sim -r ...` (auto-run flag) |
| Terminal output looks scrambled / stair-stepped | Run `stty sane` or `reset` in the terminal |
| QGC doesn't detect the drone | Confirm PX4 finished booting (see `pxh>` prompt) before opening QGC. On WSL2, you may need to manually add a UDP Comm Link on port `14550` with **Server Mode** checked |
| `bound address already in use` on port 14550 | Another process is holding the port: `sudo fuser -k 14550/udp` and/or `pkill -f QGroundControl`, then relaunch |
| Wireshark shows 0 packets | Capturing on the wrong interface — use `loopback0` in WSL2, `lo` on native Ubuntu, or the correct `vethNn`/`br-mesh` in swarm mode |
| `libfuse2` / AppImage won't launch | Re-run `sudo apt install libfuse2`, then re-`chmod +x` the AppImage |

---

## Contributing

Contributions are welcome. To propose a change:

1. Fork the repository
2. Create a branch (`git checkout -b feature/your-change`)
3. Commit your changes with a clear message
4. Open a Pull Request describing what you changed and why

See the repository's **Settings → Collaborators** if you've been added as a direct collaborator instead of contributing via fork.
