# UAV Simulation — PX4 + Gazebo + MAVLink

## Basic requirements
- Ubuntu 22.04 or 24.04 (works on both) — as a native install or inside WSL2 on Windows 10/11 (both work)
- 16GB RAM minimum
- Internet connection for the install scripts

---

## 1. Install Gazebo + PX4

```bash
cd ~
git clone https://github.com/PX4/PX4-Autopilot.git --recursive
cd PX4-Autopilot
git checkout v1.15.4
bash ./Tools/setup/ubuntu.sh
```

This single script installs **both Gazebo and all PX4 build dependencies**. Reboot after it finishes:

```bash
sudo reboot
```

Build PX4 with the Gazebo simulator target once, so it's ready to launch:

```bash
cd ~/PX4-Autopilot
make px4_sitl gz_x500
```

(Let it fully build. Once you see the simulator open and the `pxh>` prompt, it worked — close it with `Ctrl+C`.)

---

## 2. Install QGroundControl (Ubuntu)

Official steps from QGC's own docs:

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

## 3. Launch a simulation (single drone)

Open **two terminals**.

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

---

## 4. MAVLink packet capture (Wireshark)

**Key fact:** if running inside WSL2, PX4↔QGC loopback traffic goes through an interface named **`loopback0`**, not `lo`. Capturing on `lo` will show 0 packets. On native Ubuntu, capture on `lo` as normal.

Install the dissector (the `mavlink_common.lua` file in this repo):

```bash
mkdir -p ~/.local/lib/wireshark/plugins
cp mavlink_common.lua ~/.local/lib/wireshark/plugins/
```

Launch Wireshark from the terminal (not a separate GUI shortcut, so it inherits your environment):

```bash
wireshark
```

- **Interface:** `loopback0` (WSL2) or `lo` (native Ubuntu)
- **Filter:** `mavlink_proto` or `udp.port == 14550`

---

## 5. Common compatibility issues

| Issue | Fix |
|---|---|
| PX4 falls back to internal simulator instead of Gazebo, log shows "No autostart ID found" | Make sure you built with `make px4_sitl gz_x500` exactly — not `make px4_sitl` alone |
| QGC doesn't detect the drone | Confirm PX4 finished booting (see `pxh>` prompt in terminal 1) before opening QGC |
| Wireshark shows 0 packets | Capturing on wrong interface — use `loopback0` in WSL2, `lo` on native Ubuntu |
| `libfuse2` / AppImage won't launch | Re-run the `apt install libfuse2` step above, then re-chmod the AppImage |

---

## Repo contents
```
.
├── README.md
└── mavlink_common.lua   # MAVLink Wireshark dissector
```
