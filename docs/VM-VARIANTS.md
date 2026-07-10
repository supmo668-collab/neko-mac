# Insightful VM — networking variants (slirp vs vmnet)

The Insightful work VM can be created with **two independent networking backends**.
They are **fully parallel** — separate Lima instances, configs, host ports, and
launchd agents — so you can build/run the new one **without disturbing the working
one**, and even run both at the same time to A/B compare.

Everything is driven by one script (`scripts/insightful-vm.sh`) selected by the
`INSIGHTFUL_VARIANT` env var, with matching `make` targets.

## The two variants

| | **slirp** (default / original) | **vmnet** (parallel / lower-latency) |
|---|---|---|
| Status | The working VM — **unchanged** | New, opt-in |
| Networking | QEMU user-mode (slirp) | `socket_vmnet` shared NIC (direct L2 to the Mac) |
| Lima instance | `insightful-vm` | `insightful-vm-vmnet` |
| Config | `vm/lima-insightful.yaml` | `vm/lima-insightful-vmnet.yaml` |
| noVNC host port | `http://127.0.0.1:6080/vnc.html` | `http://127.0.0.1:6080/vnc.html` |
| launchd agent | `com.insightful.vm` | `com.insightful.vm.vmnet` |
| Make targets | `make vm-*` | `make vm-vmnet-*` |
| Env | (default) | `INSIGHTFUL_VARIANT=vmnet` |

Guest-side is identical (same Openbox + Chrome + Workpuls + VNC:5901 + noVNC:6080 +
the shared installers mount). Both now publish to the **same host port `:6080`** (vmnet
was moved onto the default port once slirp was retired), so **only one runs at a time** —
vmnet/KasmVNC is the one in use.

## Why vmnet

slirp (user-mode) routes the guest's packets through a userspace TCP/IP stack before
the Mac's NIC, which adds latency and **jitter** (measured: VM egress ~75 ms avg /
~79 ms mdev vs the Mac's ~52 / ~37). `socket_vmnet` gives the guest a real L2 NIC on a
shared bridge — lower, steadier latency for in-VM browsing, and a directly reachable
VM IP (`192.168.105.x`) from the Mac. Use it if the slirp VM's network feels laggy.

## Prerequisites for the vmnet variant (one-time, host side)

```bash
brew install socket_vmnet
limactl sudoers | sudo tee /etc/sudoers.d/lima   # lets Lima start the vmnet helper
```
(The slirp variant needs none of this.)

## Build / run the vmnet variant

```bash
make vm-vmnet-create        # build + start the parallel VM (long, emulated)
make vm-vmnet-url           # -> http://127.0.0.1:6080/vnc.html
make vm-vmnet-autostart     # optional: keep it always-on (its own launchd agent)
# ...vm-vmnet-{up,down,shell,tailscale,install,services,ensure,delete}
```

The original stays exactly as-is: `make vm-*` → `insightful-vm` on `:6080`. Delete the
experiment anytime with `make vm-vmnet-delete` (leaves the working VM untouched).

## One at a time (shared :6080)

Both variants now publish to host **`:6080`**, so they can't run simultaneously — start
one, `stop` it before starting the other. In practice **vmnet/KasmVNC is the primary**
and slirp is retired. (To A/B them again, temporarily set one back to a different
`hostPort` in its Lima config.)

## vmnet desktop uses KasmVNC (seamless clipboard)

The vmnet VM serves its desktop with **KasmVNC** (instead of TigerVNC + noVNC), which
provides genuine **bidirectional seamless copy/paste** and better WAN performance. It is
served over **plain HTTP** at `http://127.0.0.1:6080/` — over localhost that's still a
secure context, so the browser clipboard integration works, with **no cert warning**.

- Web client: `http://127.0.0.1:6080/` (login user **`collab`**; password set via
  `kasmvncpasswd` — reset with `limactl shell insightful-vm-vmnet -- kasmvncpasswd -u collab -w`).
- Service: systemd user unit `insightful-kasmvnc.service` (replaces `insightful-vnc` +
  `insightful-novnc` on this VM). The script's `services`/`ensure`/`autostart` target it
  automatically for the vmnet variant, and `ensure` now self-heals (restarts the desktop
  if its port stops listening).
- Config: `~/.vnc/kasmvnc.yaml` (`network.protocol: http` + `ssl.require_ssl: false`,
  `websocket_port: 6080`; a cert must still be present so `pem_certificate`/`pem_key` point
  at `~/.vnc/kasm.{crt,key}` even though TLS is off), started with `-select-de manual`.
- **Why HTTP not HTTPS:** KasmVNC's self-signed cert made the browser reject the TLS
  handshake repeatedly, which tripped KasmVNC's brute-force **IP blacklist** and made the
  site look "down." Plain HTTP over localhost avoids that entirely.

### Serving to remote/international collaborators

Kept **local-only** by default. To expose it securely to your tailnet (WireGuard-encrypted,
real Let's Encrypt HTTPS → secure context so seamless clipboard still works, no self-signed
blacklist):

```bash
make vm-vmnet-serve        # tailscale serve --bg http://127.0.0.1:6080  -> https://<mac>.<tailnet>.ts.net/
make vm-vmnet-serve-stop   # back to local-only
```

Prerequisites: enable **HTTPS Certificates** at <https://login.tailscale.com/admin/dns>
(the target checks this and tells you if it's off), and **share the `macbook-pro` node** with
the collaborator (admin → Machines → Share) so they can open the URL. Browsing still egresses
the Mac's US residential IP, so the geo requirement holds.

> KasmVNC is set up **from the start**: `make vm-vmnet-create` runs `scripts/kasmvnc-setup.sh`
> (install + SAN cert + systemd service + xstartup) then `scripts/kasmvnc-tune.sh` (the tuned
> encoding config) automatically. Re-apply / re-tune anytime with **`make vm-vmnet-kasmvnc`**
> (idempotent: install-if-missing, cert-if-missing so the Mac trust is never invalidated). The
> only manual step is the secret web login: `limactl shell insightful-vm-vmnet -- kasmvncpasswd
> -u collab -w` (password from Infisical). The base desktop (Openbox + Chrome + Workpuls) still
> comes from `vm/lima-insightful-vmnet.yaml`; only the KasmVNC streaming layer is scripted here.

## "noVNC encountered an error" — cause & fix

Diagnosed systematically with `scripts/novnc-repro.js` (headless Chrome that drives the
client for 90 s and logs console/pageerror/websocket/cert failures + the status banner):

- **Over `http` → `ws`: flawless.** 90 s of mouse/scroll/click, "Connected (unencrypted)
  to Cowork", zero drops. The server and encoder are fine — it is **not** a crash (Xvnc
  stays up; no OOM/segfault).
- **Over `https` → `wss`: `net::ERR_CERT_AUTHORITY_INVALID`.** KasmVNC's self-signed cert
  isn't trusted, so the browser refuses the `wss` channel outright (a `wss` channel can't
  show a click-through "proceed"). **That refusal is the "noVNC encountered an error."**
- KasmVNC sends **no HSTS and no redirect**, so the browser chose `https` on its own
  (bookmark / typed / Chrome's secure-connection upgrade).

**Fix (both paths clean afterward):** give the cert a matching SAN and trust it on the Mac.

```bash
# 1) SAN cert + tuned config on the guest (idempotent):
limactl shell insightful-vm-vmnet -- bash < scripts/kasmvnc-tune.sh

# 2) trust it on the Mac (one-time; pops a keychain password prompt):
limactl copy insightful-vm-vmnet:/home/mo.guest/.vnc/kasm.crt /tmp/kasm-127.crt
security add-trusted-cert -r trustRoot -k ~/Library/Keychains/login.keychain-db /tmp/kasm-127.crt

# 3) verify end-to-end (should print "Connected (encrypted) to Cowork"):
KASM_USER=collab KASM_PASS=... node scripts/novnc-repro.js /tmp/novnc.log https://127.0.0.1:6080/
```

After trust, `http`/`ws` **and** `https`/`wss` both connect clean. For remote/tailnet access,
prefer real Let's Encrypt certs via `make vm-vmnet-serve` (no manual trust needed).

### "frame error at index 0" (esp. when an agent is in debug mode)

A *different* failure from the cert one above, and the real cause is **WebP + WebCodecs**.
KasmVNC's client decodes **WebP** rects with the WebCodecs **`ImageDecoder`** API. When the
viewing browser has **no WebCodecs** — headless, an agent's "debug mode", or
`--disable-features=WebCodecs` — **every incremental WebP frame after a click fails to decode**:
`KasmVNC encountered an error: Failed to decode frame at index 0`, and the stream freezes (a
reload paints one full frame, then the next interaction re-wedges it).

**The fix (`scripts/kasmvnc-tune.sh` applies it): `webp_encoding_time: 0`** — gives WebP 0 % of
the encode budget, so rects are sent as **JPEG**, which the client decodes via the universal
`createImageBitmap` path (no WebCodecs). Video-encoding mode is *also* disabled (99 % area /
60 s; its frames need the WebCodecs `VideoDecoder`). Verified end-to-end: with
`--disable-features=WebCodecs` the WebP config threw "Failed to decode frame at index 0"
repeatedly; after `webp_encoding_time: 0`, **0 occurrences** across 90 s of clicking/scrolling.

**Manual browser-side mitigations** (if you can't apply the server fix):

- **Enable** hardware acceleration so the video decode path works: `chrome://settings/system`
  → "Use graphics acceleration when available" ON → Relaunch; verify `chrome://gpu` shows
  *Video Decode: Hardware accelerated* and WebGL not blocklisted. (Counter-intuitively,
  *disabling* accel makes video-mode frames fail, since WebCodecs then has no decoder.)
- If the browser is headless/CDP where GPU can't be enabled, launch it **without**
  `--disable-gpu`, or add `--use-gl=angle --use-angle=swiftshader` for a software GL decoder.
- Don't keep **DevTools** open on the noVNC tab — throttling/paused JS desyncs the frame decoder.
- The real fix is the server one above; the browser tweaks only help when video mode is still on.

### White-blank / "Failed to decode frame" over the tailnet (link saturation)

Forcing JPEG (the WebCodecs fix) ~triples bytes/frame vs WebP. When Claude drives over a
constrained/remote path (tailnet → the `socat 100.66.89.81:6080` raw relay → KasmVNC), a
*fat* JPEG stream **saturates the link**: frames arrive broken → `Failed to decode frame` / the
screen flashes white after each frame. Reproduced with Playwright network throttling
(`scripts/novnc-flicker.js` samples the canvas).

**WebP is NOT the answer** — verified: WebP q9 throws `Failed to decode frame` in a headless/agent
browser **even with WebCodecs enabled** (its `ImageDecoder` path is unreliable there). JPEG via
`createImageBitmap` is the only dependable decode path for how Claude drives.

**Correct profile = JPEG, sharp static text, low frame rate** (`scripts/kasmvnc-tune.sh` ships it):
save bandwidth with **frame rate, not quality**. Keep `max_quality: 9` so static text stays
**legible**, let dynamic quality soften only motion (`min_quality: 4`), and cap `max_frame_rate: 12`.
Verified: sharp/legible with WebCodecs **off**, and **0 decode-errors / 0 blanking at 2 Mbps**.
Bandwidth via fps keeps text readable (unlike lowering quality, which blurs it). On a fast local
link, raise `max_frame_rate` for smoother motion — quality is already maxed.
