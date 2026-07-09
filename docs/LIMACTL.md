# insightful-vm — limactl operations reference

Operational cheat-sheet for the **Insightful/Workpuls work VM** (`insightful-vm`), the
Lima/QEMU **amd64** Ubuntu 24.04 VM built by `scripts/insightful-vm.sh` /
`vm/lima-insightful.yaml`. Openbox desktop (Google Chrome + Workpuls) served over **noVNC**.

> All `limactl` commands run on the **host Mac**. Lima VMs + the launchd autostart are
> **per-user** — build/operate from the account that owns the VM.

---

## VM at a glance

| Item | Value |
|------|-------|
| Name | `insightful-vm` |
| Type / arch | Lima **qemu**, **x86_64** (emulated on Apple Silicon) |
| Resources | **8 vCPU / 16 GiB / 40 GiB** (`vm/lima-insightful.yaml`) |
| Guest user | `<user>` (uid 501) — **HOME = `/home/<user>.guest`** (not `/home/<user>`) |
| Desktop | Openbox + Chrome + Workpuls; TigerVNC `:1` (5901) → noVNC/websockify **:6080** |
| Local desktop URL | **`http://127.0.0.1:6080/vnc.html`** (Lima forwards 127.0.0.1:6080 → guest 6080) |
| Always-on | launchd `com.insightful.vm` (`ensure` at login + every 120 s) |
| Prereqs | `brew install lima qemu lima-additional-guestagents` |

---

## Lifecycle

```bash
limactl list                       # status of all VMs
limactl start insightful-vm        # start an existing (provisioned) VM
limactl stop  insightful-vm        # graceful stop
limactl start --tty=false <cfg>    # FIRST create only: non-interactive (skip editor prompt)
```

- **Create gotcha:** first `limactl start` **times out** ("did not receive running status")
  because emulated apt-provisioning runs long — the VM is fine, wait it out:
  `limactl shell insightful-vm -- cloud-init status --wait`
- **Resource change:** edit `cpus:` / `memory:` in `~/.lima/insightful-vm/lima.yaml` **and**
  `vm/lima-insightful.yaml`, then `limactl stop && limactl start`. Emulation is P-core-bound —
  8 vCPU is the sweet spot, not "max it out."

## Run commands / shell

```bash
limactl shell insightful-vm                        # interactive shell
limactl shell insightful-vm -- <cmd>               # one-off command
limactl shell insightful-vm -- systemctl --user status insightful-vnc insightful-novnc
```

## Desktop services (black screen / not served)

```bash
limactl shell insightful-vm -- systemctl --user restart insightful-vnc insightful-novnc
# then reload http://127.0.0.1:6080/vnc.html
```

---

## ⭐ File transfer (host ⇄ VM) — no reboot needed

**Preferred: the live shared folder (bidirectional, already mounted via the `mounts:` block).**

| Host (Mac) | Guest (VM) |
|------------|------------|
| `~/vm_setup/insightful-test/installers/` | `/home/<user>/installers/` |

- Drop a file host-side → appears in the VM **instantly** (and vice-versa). Good as a
  "drop results in / pull results out" zone.
- ⚠️ Mount lands at **`/home/<user>/installers`**, NOT the desktop home
  (`/home/<user>.guest`). Bridge it once if needed:
  `limactl shell insightful-vm -- ln -sfn /home/<user>/installers /home/<user>.guest/shared`

**Ad-hoc: `limactl copy` (the `docker cp` equivalent, rsync/scp-backed).** Prefix the guest
side with `insightful-vm:`.

```bash
limactl copy ./file.csv insightful-vm:/home/<user>.guest/Desktop/    # push in
limactl copy insightful-vm:/home/<user>.guest/out.csv ./             # pull out
```

> Prefer the mount / `limactl copy` over a Google Drive client in the VM — the latter needs an
> install + interactive OAuth + an always-on sync daemon (extra load on an emulated VM) and
> routes files through the cloud. Local transfer is simpler and faster.

---

## Gotchas (so future sessions don't re-hit them)

- **User/home mismatch:** guest user `<user>` has HOME `/home/<user>.guest`, but the installers
  mount is `/home/<user>/installers`. Openbox autostart checks `$HOME/installers`
  (`/home/<user>.guest/installers`), so a file in the host mount is **not auto-found** — copy it
  to `/home/<user>.guest/installers/` and restart the VNC session. (Root fix: patch the yaml
  `mountPoint` to the real home.)
- **Workpuls auto-open:** needs `Workpuls.AppImage` (x86-64) in `/home/<user>.guest/installers/`;
  Openbox autostart runs it `--no-sandbox`. Persists across restarts (local ext4).
- **noVNC clipboard** needs a bridge (added to `~/.config/openbox/autostart`):
  `vncconfig -nowin & ; autocutsel -fork & ; autocutsel -selection PRIMARY -fork &`. noVNC 1.3.0
  = manual clipboard panel only; seamless Cmd+V needs noVNC ≥1.5 over HTTPS/localhost.

---

## Latency guidance (remote user)

- Serve the desktop via the **Mac's Tailscale**, not tailscale-inside-the-VM: QEMU slirp
  networking can't hole-punch → DERP relay (extra hop); the Mac gets a direct WireGuard path.
  Use `tailscale serve` (host, HTTPS) in front of `127.0.0.1:6080` (HTTPS also enables seamless
  clipboard). Verify direct-not-relayed with `tailscale ping <node>`.
- No-VM-change tuning: noVNC lower **Quality** (~5) + raise **Compression**.
- Needs-VM-change wins: slirp → `socket_vmnet`; lower VNC geometry/depth; or swap VNC for a
  WebRTC desktop (KasmVNC/Selkies). Floor: US host + user abroad ≈ 100–150 ms geographic RTT.

---

## Make targets

```bash
make vm-up | vm-down | vm-url | vm-shell | vm-status
make vm-ensure         # idempotent start + services (what launchd runs)
make vm-autostart | vm-autostart-remove
```
