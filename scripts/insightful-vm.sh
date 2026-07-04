#!/usr/bin/env bash
# Manage the full Insightful/Workpuls Lima VM (real systemd session, FUSE, keyring).
# This is separate from the neko stack and the Docker test desktop.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_NAME="insightful-vm"
CONFIG="$ROOT_DIR/vm/lima-insightful.yaml"

usage() {
  cat <<'USAGE'
Usage: scripts/insightful-vm.sh <command>

Commands:
  create     Create and start the VM from vm/lima-insightful.yaml
  start      Start an existing VM
  stop       Stop the VM
  shell      Open a shell inside the VM
  services   Enable linger and start the VNC + noVNC desktop services
  tailscale  Run 'tailscale up' inside the VM (interactive auth)
  install    Run the Workpuls install/launch helper inside the VM
  url        Print local and Tailscale desktop URLs
  status     Show VM status
  delete     Delete the VM (destructive)

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
