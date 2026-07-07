#!/usr/bin/env bash
# Manage the full Insightful/Workpuls Lima VM (real systemd session, FUSE, keyring).
# This is separate from the neko stack and the Docker test desktop.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_NAME="insightful-vm"
CONFIG="$ROOT_DIR/vm/lima-insightful.yaml"

# launchd (always-on) settings.
LAUNCHD_LABEL="com.insightful.vm"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"
LAUNCHD_LOG="$HOME/Library/Logs/insightful-vm.autostart.log"

usage() {
  cat <<'USAGE'
Usage: scripts/insightful-vm.sh <command>

Commands:
  create           Create and start the VM from vm/lima-insightful.yaml
  start            Start an existing VM
  stop             Stop the VM
  shell            Open a shell inside the VM
  services         Enable linger and start the VNC + noVNC desktop services
  tailscale        Run 'tailscale up' inside the VM (interactive auth)
  install          Run the Workpuls install/launch helper inside the VM
  url              Print local and Tailscale desktop URLs
  status           Show VM status
  ensure           Start the VM + services if not already running (idempotent)
  autostart        Install a launchd agent so the VM is always on (runs at login)
  autostart-remove Remove the launchd agent (stop keeping the VM always on)
  delete           Delete the VM (destructive)

Access after 'create' + 'services':
  Local : http://127.0.0.1:6080/vnc.html
  Remote: http://<vm-tailscale-ip>:6080/vnc.html  (after 'tailscale')
USAGE
}

vm_ip() {
  limactl shell "$VM_NAME" -- tailscale ip -4 2>/dev/null | head -1 || true
}

cmd="${1:-help}"
case "$cmd" in
  create)
    limactl start --name "$VM_NAME" "$CONFIG"
    "$0" services
    "$0" url
    ;;
  start)
    limactl start "$VM_NAME"
    ;;
  stop)
    limactl stop "$VM_NAME"
    ;;
  shell)
    shift || true
    limactl shell "$VM_NAME" -- "${@:-bash}"
    ;;
  services)
    limactl shell "$VM_NAME" -- sudo loginctl enable-linger "$(limactl shell "$VM_NAME" -- whoami)"
    limactl shell "$VM_NAME" -- systemctl --user daemon-reload
    limactl shell "$VM_NAME" -- systemctl --user enable --now insightful-vnc.service insightful-novnc.service
    echo "Desktop services started."
    ;;
  tailscale)
    limactl shell "$VM_NAME" -- sudo tailscale up
    ;;
  install)
    limactl shell "$VM_NAME" -- bash -lc '~/install-insightful.sh'
    ;;
  url)
    echo "Local desktop : http://127.0.0.1:6080/vnc.html"
    ip="$(vm_ip)"
    if [ -n "$ip" ]; then
      echo "Tailscale     : http://$ip:6080/vnc.html"
    else
      echo "Tailscale     : run 'scripts/insightful-vm.sh tailscale' first"
    fi
    ;;
  status)
    limactl list | sed -n '1p'; limactl list | grep -E "^$VM_NAME" || true
    ;;
  ensure)
    # Idempotent "keep it alive" step, safe to call repeatedly (used by launchd).
    status="$(limactl list --format '{{.Status}}' "$VM_NAME" 2>/dev/null || true)"
    if [ "$status" != "Running" ]; then
      echo "[ensure] VM status='$status' -> starting"
      limactl start "$VM_NAME"
    fi
    # Bring the desktop services up (no-op if already active).
    user="$(limactl shell "$VM_NAME" -- whoami)"
    limactl shell "$VM_NAME" -- sudo loginctl enable-linger "$user" >/dev/null 2>&1 || true
    limactl shell "$VM_NAME" -- systemctl --user enable --now \
      insightful-vnc.service insightful-novnc.service >/dev/null 2>&1 || true
    echo "[ensure] VM running; desktop at http://127.0.0.1:6080/vnc.html"
    ;;
  autostart)
    # Install a per-user launchd agent that keeps the VM always on: it runs the
    # 'ensure' command at login and re-checks every 2 minutes, restarting the VM
    # (and desktop services) if it is ever stopped.
    mkdir -p "$(dirname "$LAUNCHD_PLIST")" "$(dirname "$LAUNCHD_LOG")"
    cat > "$LAUNCHD_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LAUNCHD_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$ROOT_DIR/scripts/insightful-vm.sh</string>
    <string>ensure</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>120</integer>
  <key>ThrottleInterval</key>
  <integer>120</integer>
  <key>StandardOutPath</key>
  <string>$LAUNCHD_LOG</string>
  <key>StandardErrorPath</key>
  <string>$LAUNCHD_LOG</string>
  <key>WorkingDirectory</key>
  <string>$ROOT_DIR</string>
</dict>
</plist>
PLIST
    # Reload cleanly whether or not it was already installed.
    launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$LAUNCHD_PLIST"
    launchctl enable "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null || true
    echo "✓ Always-on enabled. Agent: $LAUNCHD_PLIST"
    echo "  Log: $LAUNCHD_LOG"
    echo "  The VM will start at login and stay up (re-checked every 120s)."
    ;;
  autostart-remove)
    launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null || true
    rm -f "$LAUNCHD_PLIST"
    echo "✓ Always-on disabled. The VM will no longer auto-start."
    echo "  (The VM itself is untouched; use 'stop' to shut it down.)"
    ;;
  delete)
    limactl stop "$VM_NAME" 2>/dev/null || true
    limactl delete "$VM_NAME"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
