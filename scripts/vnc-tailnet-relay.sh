#!/usr/bin/env bash
# WebSocket-stable tailnet relay for the KasmVNC desktop.
#
# Publishes the vmnet VM's desktop on the Mac's Tailscale IP and forwards it DIRECTLY to the
# guest's vmnet L2 IP (192.168.105.x) — NOT the Lima `127.0.0.1:6080` port-forward, which Lima
# tunnels over SSH and which STALLS/DROPS sustained high-bandwidth websockets (that was the
# cause of the KasmVNC link erroring every few minutes while Claude drove it). Also sets TCP
# keepalive + nodelay so half-open/idle connections through WireGuard NAT are kept alive and
# small interactive frames aren't Nagle-buffered.
#
# Managed by launchd (~/Library/LaunchAgents/com.neko.novnc-tailnet-proxy.plist, KeepAlive=true),
# so if it exits (e.g. the guest IP changed after a rebuild) launchd restarts it and it re-resolves.
set -uo pipefail

TS_BIN="$(command -v tailscale || echo /opt/homebrew/bin/tailscale)"
SOCAT="$(command -v socat || echo /opt/homebrew/bin/socat)"
VM_NAME="${VM_NAME:-insightful-vm-vmnet}"
PORT="${PORT:-6080}"
KA="keepalive,nodelay"   # macOS socat lacks keepidle/keepintvl/keepcnt; keepalive+nodelay is portable

# Portable timeout (macOS ships no `timeout`) so a wedged guest never hangs the relay.
run_to() {
  local t="$1"; shift
  "$@" & local p=$!
  ( sleep "$t"; kill -TERM "$p" 2>/dev/null ) >/dev/null 2>&1 & local w=$!
  local rc=0
  wait "$p" 2>/dev/null || rc=$?
  kill -TERM "$w" 2>/dev/null || true; wait "$w" 2>/dev/null || true
  return $rc
}

ts_ip() { "$TS_BIN" ip -4 2>/dev/null | head -1; }

guest_ip() {
  # Prefer the stable default and verify it actually serves (curl exits 0 even on 401);
  # only fall back to live limactl resolution if that fails.
  local ip="${GUEST_IP:-192.168.105.2}"
  if run_to 6 curl -sS -o /dev/null -m 5 "http://$ip:$PORT/"; then echo "$ip"; return 0; fi
  run_to 25 limactl shell "$VM_NAME" -- bash -lc \
    'ip -4 addr show lima0 2>/dev/null | grep -oE "inet [0-9.]+" | awk "{print \$2}"' 2>/dev/null | head -1
}

TS=""; GIP=""
for _ in $(seq 1 60); do
  TS="$(ts_ip)"; GIP="$(guest_ip)"
  [ -n "$TS" ] && [ -n "$GIP" ] && break
  sleep 5
done
[ -n "$TS" ] && [ -n "$GIP" ] || { echo "relay: endpoints not ready (ts='$TS' guest='$GIP')"; exit 1; }

echo "relay: $TS:$PORT -> $GIP:$PORT ($KA, direct vmnet — bypasses Lima SSH forward)"
exec "$SOCAT" "TCP-LISTEN:$PORT,bind=$TS,fork,reuseaddr,$KA" "TCP:$GIP:$PORT,$KA"
