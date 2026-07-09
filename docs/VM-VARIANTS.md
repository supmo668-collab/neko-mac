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
