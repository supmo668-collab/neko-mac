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
| noVNC host port | `http://127.0.0.1:6080/vnc.html` | `http://127.0.0.1:6081/vnc.html` |
| launchd agent | `com.insightful.vm` | `com.insightful.vm.vmnet` |
| Make targets | `make vm-*` | `make vm-vmnet-*` |
| Env | (default) | `INSIGHTFUL_VARIANT=vmnet` |

Guest-side is identical (same Openbox + Chrome + Workpuls + VNC:5901 + noVNC:6080 +
the shared installers mount). Only the **host networking + host port** differ, so the
two never collide.

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
make vm-vmnet-url           # -> http://127.0.0.1:6081/vnc.html
make vm-vmnet-autostart     # optional: keep it always-on (its own launchd agent)
# ...vm-vmnet-{up,down,shell,tailscale,install,services,ensure,delete}
```

The original stays exactly as-is: `make vm-*` → `insightful-vm` on `:6080`. Delete the
experiment anytime with `make vm-vmnet-delete` (leaves the working VM untouched).

## Running both at once

Because they use different instances and host ports, both desktops can be open
simultaneously — `:6080` (slirp) and `:6081` (vmnet) — which is the intended way to
compare responsiveness before deciding whether to switch.

## vmnet desktop uses KasmVNC (seamless clipboard)

The vmnet VM serves its desktop with **KasmVNC** (instead of TigerVNC + noVNC), which
provides genuine **bidirectional seamless copy/paste** and better WAN performance. It is
served over **plain HTTP** at `http://127.0.0.1:6081/` — over localhost that's still a
secure context, so the browser clipboard integration works, with **no cert warning**.

- Web client: `http://127.0.0.1:6081/` (login user **`collab`**; password set via
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
make vm-vmnet-serve        # tailscale serve --bg http://127.0.0.1:6081  -> https://<mac>.<tailnet>.ts.net/
make vm-vmnet-serve-stop   # back to local-only
```

Prerequisites: enable **HTTPS Certificates** at <https://login.tailscale.com/admin/dns>
(the target checks this and tells you if it's off), and **share the `macbook-pro` node** with
the collaborator (admin → Machines → Share) so they can open the URL. Browsing still egresses
the Mac's US residential IP, so the geo requirement holds.

> NOTE: KasmVNC was set up on the *running* vmnet VM (runtime), not yet baked into
> `vm/lima-insightful-vmnet.yaml` provisioning — a fresh `make vm-vmnet-create` would come
> up with the base noVNC until the KasmVNC steps are added to the config's provision block.
