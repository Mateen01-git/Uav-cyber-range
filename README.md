# Multi-UAV Simulation Framework (PX4 SITL + Gazebo + MAVLink)

A simulation environment for both a **single simulated drone** and a **multi-drone swarm**, built on **PX4 Autopilot (v1.15.4)**, **Gazebo Sim**, **QGroundControl**, and **MAVLink**. Swarm mode adds Linux network namespaces and `mavlink-router` so each drone behaves like an isolated, independent vehicle instead of sharing one internal network.

Tested on Ubuntu 22.04 / 24.04, native or inside WSL2 (Windows 10/11).

---

## Repository Contents

```
.
├── README.md                          # This file
├── mavlink_common.lua                 # Wireshark MAVLink dissector
├── run_single_drone.sh                # One-command single-drone launcher (recommended)
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

Let it fully build. **Note (WSL2 users):** running `make px4_sitl gz_x500` bare like this often fails on WSL2 with `ERROR [gz_bridge] Service call timed out` because Gazebo's GUI hangs waiting on graphics drivers. This is expected the first time — don't worry about it here, it's fixed by the launcher script in Section 4. This first build is just to confirm the binary compiles; once you see it attempt to start (even if it errors on `gz_bridge`), the build itself succeeded — close it with `Ctrl+C`.

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

> **Important:** on WSL2, running `make px4_sitl gz_x500` directly (the "manual" method below) frequently fails with a Gazebo timeout. **`./run_single_drone.sh` is the reliable method** — use it unless you're on native Ubuntu with working GPU passthrough.

### Recommended: One-command launcher

```bash
cd ~
./run_single_drone.sh
```

This script does the following automatically, in order:
1. Kills any stray/zombie Gazebo, PX4, or Ruby processes from previous runs
2. Resets terminal formatting (`stty sane`)
3. Forces software OpenGL rendering (`LIBGL_ALWAYS_SOFTWARE=1`) so Gazebo doesn't hang waiting on WSL2's GPU passthrough
4. Sets `GZ_SIM_RESOURCE_PATH` so Gazebo can find PX4's drone models/worlds
5. Launches Gazebo **already running** (`-r` flag) instead of paused, avoiding the "timed out waiting for clock message" error
6. Waits a few seconds for Gazebo to settle, then starts PX4 SITL

Once you see `pxh>` and the drone spawns in the Gazebo window, it worked.

Then open QGroundControl:
```bash
cd ~
./QGroundControl.AppImage
```

If it doesn't auto-connect:
`QGC icon (top-left) → Application Settings → Comm Links → Add`
- Type: `UDP`
- Port: `14550`
- Check **Server Mode**
- Click **OK**, select it, click **Connect**

### Manual method (fallback / native Ubuntu only)

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

If this hangs with `ERROR [gz_bridge] Service call timed out`, stop and use `./run_single_drone.sh` instead — don't keep retrying the manual method on WSL2, it's a known environment limitation, not a bug in your setup.

---

## 5. Mode 2 — Multi-Drone Swarm

**Why:** Running several PX4 instances directly on the host means they all share the same internal network — not realistic for testing real swarm communication or network-level attacks. The `swarm-mesh/` scripts give each simulated drone its own isolated Linux network namespace with its own virtual network interface and IP, connected through a virtual bridge (`br-mesh`) — similar to how physically separate drones would talk to each other over radio.

### 5.1 Additional dependencies (install once, before first swarm run)

The single-drone setup script (Section 2) does **not** install these — they're only needed for swarm mode:

```bash
# tmux — runs each PX4 instance in its own background session
sudo apt install tmux -y

# mavlink-router — routes MAVLink UDP traffic between namespaces and QGC
sudo apt install git ninja-build pkg-config gcc g++ systemd python3-pip -y
pip3 install meson --break-system-packages
cd ~
git clone https://github.com/mavlink-router/mavlink-router.git
cd mavlink-router
git submodule update --init --recursive
meson setup build .
ninja -C build
sudo ninja -C build install
```

Verify it installed correctly:
```bash
cd ~/Uav-cyber-range/swarm-mesh
./check_mavlink_router.sh
```
You should see `[+] Found at: /usr/local/bin/mavlink-routerd` (or similar) and its version.

`ip netns`, `ip link`, and the bridge tools used by `setup_dynamic_swarm_mesh.sh` come from the `iproute2` package, which is installed by default on Ubuntu — no action needed unless you get a `command not found` on `ip`.

### 5.2 Network layout

| Node | Namespace | Interface | Static IP | MAVLink Port | Forwards To |
|---|---|---|---|---|---|
| Host / QGC | *(host)* | `br-mesh` | `10.10.0.1` | `14550` | — |
| Drone 0 | `drone0` | `veth0n` | `10.10.0.10/24` | `14560` | `10.10.0.1:14550` |
| Drone 1 | `drone1` | `veth1n` | `10.10.0.11/24` | `14561` | `10.10.0.1:14550` |
| Drone N | `droneN` | `vethNn` | `10.10.0.1(N+10)/24` | `1456N` | `10.10.0.1:14550` |

### 5.3 Step-by-step execution (N = number of drones, e.g. 2)

```bash
# 1. Build the virtual mesh network (bridge + namespaces + IPs)
cd ~/Uav-cyber-range/swarm-mesh
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
cd ~
./QGroundControl.AppImage
```

QGroundControl listens on `10.10.0.1:14550` and will show one vehicle icon per drone (SysID 1, 2, 3…), each fed by its own isolated namespace and router.

### 5.4 Verifying drones are actually talking

```bash
# Ping Drone 1 from Drone 0's namespace
sudo ip netns exec drone0 ping 10.10.0.11 -c 4

# Watch live MAVLink packets arriving on Drone 1's interface
sudo ip netns exec drone1 tcpdump -i veth1n udp port 14561 -c 5
```

### 5.5 Attaching to an individual drone's console

Each PX4 instance runs inside a `tmux` session inside its own namespace:
```bash
sudo ip netns exec drone0 tmux attach -t px4_0
```
Detach without killing it: `Ctrl+B` then `D`.

### 5.6 Stopping / cleaning up

```bash
# Kill every process and remove the virtual network cleanly
~/Uav-cyber-range/swarm-mesh/stop_all.sh

# Or just tear down the network namespaces/bridge (leaves processes running)
~/Uav-cyber-range/swarm-mesh/teardown_swarm_mesh.sh 2
```

> **Note:** Single-drone mode (`run_single_drone.sh`) and swarm mode (`swarm-mesh/`) don't interfere with each other — running one doesn't break the other's scripts or configuration.

---

## 6. MAVLink Packet Capture (Wireshark)

### 6.1 Install Wireshark (if not already installed)
```bash
sudo apt install wireshark -y
```
During install, if asked "Should non-superusers be able to capture packets?" — choose **Yes**, then add your user to the `wireshark` group and re-login:
```bash
sudo usermod -aG wireshark $USER
```
Log out and back in for this to apply.

### 6.2 Install the MAVLink dissector plugin

The dissector file `mavlink_common.lua` is included in this repo. Copy it into Wireshark's plugin folder:

```bash
mkdir -p ~/.local/lib/wireshark/plugins
cp ~/Uav-cyber-range/mavlink_common.lua ~/.local/lib/wireshark/plugins/
```

Restart Wireshark if it was already open for the plugin to load. You can confirm it loaded via `Help → About Wireshark → Plugins` — `mavlink_common.lua` should be listed.

### 6.3 Capturing traffic

**Key fact:** if running inside WSL2, PX4↔QGC loopback traffic goes through an interface named `loopback0`, not `lo`. Capturing on `lo` will show 0 packets. On native Ubuntu, capture on `lo` as normal. For swarm mode, capture on the individual `vethNn` interface inside the relevant namespace, or on `br-mesh` to see all mesh traffic.

Launch Wireshark from the terminal (not a separate GUI shortcut, so it inherits your environment):

```bash
wireshark
```

- **Interface:** `loopback0` (WSL2, single drone) · `lo` (native Ubuntu, single drone) · `br-mesh` or a specific `vethNn` inside a namespace (swarm mode)
- **Filter:** `mavlink_proto` or `udp.port == 14550`

For swarm-mode namespace capture without opening the Wireshark GUI inside the namespace, use `tcpdump` and open the resulting file in Wireshark afterward:
```bash
sudo ip netns exec drone0 tcpdump -i veth0n -w ~/drone0_capture.pcap udp port 14560
```
Then open `~/drone0_capture.pcap` in Wireshark normally (Ctrl+C to stop the capture first).

---

## 7. Common Compatibility Issues

| Issue | Fix |
|---|---|
| PX4 falls back to internal simulator instead of Gazebo, log shows "No autostart ID found" | Make sure you built with `make px4_sitl gz_x500` exactly — not `make px4_sitl` alone |
| `ERROR [gz_bridge] Service call timed out` | Known WSL2 issue — Gazebo froze on graphics init. Don't retry the bare `make px4_sitl gz_x500` command; use `./run_single_drone.sh` instead |
| Gazebo window opens but is blank / drone not visible | Simulation is paused. Click the **Play ▶** button in Gazebo, or make sure you're using `run_single_drone.sh` (which runs Gazebo un-paused via `-r`) |
| Terminal output looks scrambled / stair-stepped | Run `stty sane` or `reset` in the terminal |
| QGC doesn't detect the drone | Confirm PX4 finished booting (see `pxh>` prompt) before opening QGC. On WSL2, you may need to manually add a UDP Comm Link on port `14550` with **Server Mode** checked |
| `bound address already in use` on port 14550 | Another process is holding the port: `sudo fuser -k 14550/udp` and/or `pkill -f QGroundControl`, then relaunch |
| `mavlink-routerd: command not found` | Install it — see Section 5.1 |
| Wireshark shows 0 packets | Capturing on the wrong interface — use `loopback0` in WSL2, `lo` on native Ubuntu, or the correct `vethNn`/`br-mesh` in swarm mode |
| `libfuse2` / AppImage won't launch | Re-run `sudo apt install libfuse2`, then re-`chmod +x` the AppImage |

---

## 8. Pushing an Updated Version of a File to the Repo

Whenever you edit any file locally (README, a script, the lua plugin, etc.), the update process is always the same:

```bash
cd ~/Uav-cyber-range

# stage the changed file(s) — this works whether the file is new or already tracked
git add README.md
# or stage everything that changed:
# git add .

git commit -m "Describe what you changed here"
git push
```

`git add` + `git commit` + `git push` will **overwrite** whatever version is currently on GitHub with your local version — you never need to manually delete the old file first, Git replaces it automatically as long as the filename/path is identical.

To confirm what changed before committing:
```bash
git status      # shows which files are modified/new
git diff        # shows line-by-line changes
```

---

## 9. Adding a Contributor — Complete Steps

There is **no shared "ticket" or token** — every contributor goes through this individually.

**You (repo owner) do this once per person:**
1. Go to `https://github.com/Mateen01-git/Uav-cyber-range`
2. `Settings → Collaborators → Add people`
3. Enter their email address → click **Add**
4. GitHub emails them an invite

**Each contributor then does this on their own machine:**
1. Accept the invite from their email (creating a GitHub account first if they don't have one)
2. Install git if not already installed: `sudo apt install git -y`
3. Configure their identity:
   ```bash
   git config --global user.name "Their Name"
   git config --global user.email "their-email@example.com"
   ```
4. Clone the repo:
   ```bash
   cd ~
   git clone https://github.com/Mateen01-git/Uav-cyber-range.git
   cd Uav-cyber-range
   ```
5. Generate their **own** personal access token (needed since GitHub no longer accepts plain passwords for git operations):
   `GitHub → profile icon (top-right) → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token`
   - Check the `repo` scope
   - Set an expiration
   - Copy the token somewhere safe — GitHub only shows it once
6. Make changes, then push:
   ```bash
   git add .
   git commit -m "What I changed"
   git push
   ```
   When prompted:
   - Username: their GitHub username
   - Password: **paste their personal access token** (not their GitHub account password)

Each person's token is tied to their own account and their own permissions — nobody uses your token, and you don't use theirs.

---

## Contributing

Contributions are welcome. To propose a change:

1. Fork the repository (or work directly if added as a collaborator — see Section 9)
2. Create a branch (`git checkout -b feature/your-change`)
3. Commit your changes with a clear message
4. Open a Pull Request describing what you changed and why
