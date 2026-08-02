#!/usr/bin/env bash
echo "[*] Checking mavlink-router installation..."

if command -v mavlink-routerd >/dev/null 2>&1; then
    echo "[+] Found at: $(command -v mavlink-routerd)"
    mavlink-routerd --version
else
    echo "[!] mavlink-routerd not found in PATH."
    exit 1
fi

echo
echo "[*] Checking for a running instance..."
if pgrep -f mavlink-routerd >/dev/null; then
    echo "[+] mavlink-routerd is currently running (PID(s): $(pgrep -f mavlink-routerd | xargs))"
else
    echo "[-] No mavlink-routerd process currently running."
fi
