#!/usr/bin/env bash
# Apply the tuned, stable KasmVNC desktop config + a SAN cert to the vmnet work VM.
# This captures the runtime fixes worked out for the Claude-driven VNC session:
#   - stability: loosen the brute-force lockout, shared session, no idle/auto-shutdown
#   - latency:   cap frame rate to the software-WebP encode capacity, dynamic quality
#   - the noVNC "encountered an error" fix: a cert with a matching 127.0.0.1 SAN so the
#     browser can trust it (see docs/VM-VARIANTS.md for the one-time Mac `security` step)
#
# Run INSIDE the guest:
#   limactl shell insightful-vm-vmnet -- bash < scripts/kasmvnc-tune.sh
set -euo pipefail

VNC="$HOME/.vnc"
mkdir -p "$VNC"

# SAN cert (CN + SAN must include the host the browser hits: 127.0.0.1 via the Lima forward).
# Untrusted self-signed with NO matching SAN is what made wss fail -> "noVNC encountered an error".
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$VNC/kasm.key" -out "$VNC/kasm.crt" -days 3650 \
  -subj "/CN=127.0.0.1" \
  -addext "subjectAltName=IP:127.0.0.1,DNS:localhost" 2>/dev/null
echo "cert SAN: $(openssl x509 -in "$VNC/kasm.crt" -noout -ext subjectAltName 2>/dev/null | tail -1 | tr -s ' ')"

cat > "$VNC/kasmvnc.yaml" <<YAML
network:
  protocol: http
  interface: 0.0.0.0
  websocket_port: 6080
  ssl:
    require_ssl: false
    pem_certificate: $VNC/kasm.crt
    pem_key: $VNC/kasm.key
desktop:
  resolution:
    width: 1280
    height: 720
security:
  brute_force_protection:
    blacklist_threshold: 100   # default 5 locks out reconnects/retries -> looked "down"
    blacklist_timeout: 1
user_session:
  session_type: shared         # a reconnect JOINS instead of being refused
  idle_timeout: never
server:
  auto_shutdown:
    no_user_session_timeout: never
    active_user_session_timeout: never
    inactive_user_session_timeout: never
encoding:
  max_frame_rate: 30           # software WebP ~35 ms/frame (~28 fps ceiling); 60 over-drove it
  rect_encoding_mode:
    min_quality: 5             # faster encode during motion -> lower input latency
    max_quality: 9             # settled frames go sharp...
    consider_lossless_quality: 10  # ...then lossless -> legible screenshots for an agent
  video_encoding_mode:
    enter_video_encoding_mode:
      time_threshold: 2
      area_threshold: 45%
    exit_video_encoding_mode:
      time_threshold: 1        # return to a sharp frame ~1 s after an action (was 3 s)
    # NOTE: do NOT try to "disable" video mode with extreme values (e.g. time_threshold
    # 999999 / area 100%) -> the wrapper emits a bad arg and Xvnc fails: "Unrecognized
    # option: -VideoTime".
YAML

systemctl --user restart insightful-kasmvnc.service
sleep 4
echo "kasmvnc active: $(systemctl --user is-active insightful-kasmvnc.service)"
echo "listening 6080: $(ss -tln | grep -q ':6080 ' && echo yes || echo no)"
