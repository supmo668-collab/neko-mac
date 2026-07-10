#!/usr/bin/env bash
# Idempotent KasmVNC-LAYER setup for the vmnet Insightful desktop, so a build has the correct
# streaming stack "from the start" instead of runtime hand-patching. Handles: install, SAN cert
# (once), the systemd user service, and the session xstartup. The ENCODING config lives in
# kasmvnc-tune.sh (run it after this). The web-login password is a secret and is NOT set here.
#
# Run INSIDE the guest (the orchestrator does this for you on `create`):
#   limactl shell insightful-vm-vmnet -- bash < scripts/kasmvnc-setup.sh
#   limactl shell insightful-vm-vmnet -- bash < scripts/kasmvnc-tune.sh
set -euo pipefail
VNC="$HOME/.vnc"; SVC="$HOME/.config/systemd/user"
mkdir -p "$VNC" "$SVC"

# 1) Install kasmvncserver (Ubuntu 24.04 "noble", amd64) if missing.
#    Bump KASMVNC_VER when upgrading; the release asset name follows this pattern.
KASMVNC_VER="${KASMVNC_VER:-1.4.0}"
if ! command -v kasmvncserver >/dev/null 2>&1; then
  deb="/tmp/kasmvncserver_noble.deb"
  curl -fsSL -o "$deb" \
    "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VER}/kasmvncserver_noble_${KASMVNC_VER}_amd64.deb"
  sudo apt-get update -qq
  sudo apt-get install -y -qq "$deb"
fi
echo "kasmvncserver: $(dpkg -l | grep -i '^ii  kasmvncserver' | tr -s ' ' | cut -d' ' -f3 || echo '?')"

# 2) Session xstartup (dbus + gnome-keyring + openbox) — used because the service starts with
#    `-select-de manual`, which runs ~/.vnc/xstartup instead of prompting for a desktop env.
cat > "$VNC/xstartup" <<'X'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XKL_XMODMAP_DISABLE=1
eval "$(dbus-launch --sh-syntax)"
eval "$(echo '' | gnome-keyring-daemon --start --components=secrets,pkcs11 2>/dev/null || true)"
export DBUS_SESSION_BUS_ADDRESS SSH_AUTH_SOCK
exec openbox-session
X
chmod +x "$VNC/xstartup"

# 3) SAN cert — ONLY if missing. Regenerating it would invalidate the Mac's login-keychain
#    trust (see docs/VM-VARIANTS.md), so never overwrite an existing one here.
if [ ! -f "$VNC/kasm.crt" ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$VNC/kasm.key" -out "$VNC/kasm.crt" -days 3650 \
    -subj "/CN=127.0.0.1" -addext "subjectAltName=IP:127.0.0.1,DNS:localhost" 2>/dev/null
  echo "cert: generated (SAN 127.0.0.1/localhost) -> trust it on the Mac, see docs/VM-VARIANTS.md"
else
  echo "cert: present (kept)"
fi

# 4) systemd user service (Type=oneshot+RemainAfterExit; Xvnc IS the :1 X server).
cat > "$SVC/insightful-kasmvnc.service" <<'UNIT'
[Unit]
Description=KasmVNC server for Insightful desktop
After=default.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/usr/bin/kasmvncserver -kill :1
ExecStart=/usr/bin/kasmvncserver :1 -desktop Cowork -select-de manual -geometry 1280x720 -depth 24
ExecStop=/usr/bin/kasmvncserver -kill :1
[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload

# 5) Web-login password (secret — NOT stored in the repo). Set once:
if [ ! -f "$HOME/.kasmpasswd" ]; then
  echo "NOTE: web login not set. Run:  kasmvncpasswd -u collab -w   (password from Infisical, do not commit)"
fi
echo "kasmvnc-setup: done. Now apply the encoding config with kasmvnc-tune.sh, then enable the service."
