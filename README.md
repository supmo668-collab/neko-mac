# neko-mac

Spin up a **shared remote browser** on a Mac and reach it securely from anywhere over
[Tailscale](https://tailscale.com/) — powered by [neko](https://github.com/m1k1o/neko).
One admin drives, everyone else watches. No ports exposed to the public internet.

```
make setup     # install OrbStack + Tailscale, create .env, detect Tailscale IP
make up        # start the remote browser
make url       # print the access URLs + login
```

---

## Requirements

- macOS (Apple Silicon or Intel)
- A Tailscale account (free)
- `make` + `git` (preinstalled on macOS)

`make setup` installs the rest (Homebrew, OrbStack for Docker, Tailscale).

---

## Quick start

```bash
git clone https://github.com/<you>/neko-mac.git
cd neko-mac

make setup                      # installs deps, creates .env, fills TAILSCALE_IP
$EDITOR .env                    # set ADMIN_PASSWORD / VIEWER_PASSWORD
make up                         # start it
make url                        # show URLs + login
```

If Tailscale prompts you to sign in during `make setup`, complete it (menu bar or
`tailscale login`) and re-run `make setup`.

---

## Access

| Network                           | URL                          |
| --------------------------------- | ---------------------------- |
| Local (same Mac)                  | `http://localhost:8080`      |
| Tailscale (any device on Tailnet) | `http://<TAILSCALE_IP>:8080` |

`make url` prints both. To let others in, invite them to your Tailnet — they install
Tailscale, then open the Tailscale URL. Traffic is WireGuard-encrypted end to end.

### Logins

| Role   | Username (default) | Can do                                       |
| ------ | ------------------ | -------------------------------------------- |
| Admin  | `collab`           | Full keyboard + mouse control of the browser |
| Viewer | `viewer`           | Watch only — can never take control          |

Passwords live in `.env` (`ADMIN_PASSWORD` / `VIEWER_PASSWORD`).

> **Only one person uses the admin login.** Two admin sessions fight over the single
> control slot ("took over control" ping-pong). Hand everyone else the viewer login.

To take control: connect as admin and click the screen once — control is granted
automatically and stays yours.

---

## Configuration

All knobs live in `.env` (copied from [`.env.example`](.env.example)). Change a value,
then `make restart`.

| Variable                          | Default                              | Purpose                                       |
| --------------------------------- | ------------------------------------ | --------------------------------------------- |
| `NEKO_IMAGE`                      | `ghcr.io/m1k1o/neko/chromium:latest` | Browser image (see below)                     |
| `ADMIN_USER` / `ADMIN_PASSWORD`   | `collab` / —                         | Admin login                                   |
| `VIEWER_USER` / `VIEWER_PASSWORD` | `viewer` / —                         | Viewer login                                  |
| `NEKO_SCREEN`                     | `1920x1080@30`                       | Resolution & FPS (`WxH@FPS`)                  |
| `HTTP_PORT`                       | `8080`                               | Web UI port                                   |
| `MUX_PORT`                        | `52000`                              | Single WebRTC media port (UDP + TCP)          |
| `SHM_SIZE`                        | `2gb`                                | Browser shared memory (raise for heavy pages) |
| `TAILSCALE_IP`                    | auto (`make ip`)                     | IP advertised for WebRTC                       |

**Switch browser** by changing the image app segment:
`ghcr.io/m1k1o/neko/{chromium,firefox,brave,vivaldi,google-chrome,ungoogled-chromium}:latest`

---

## Make targets

| Target         | Description                                      |
| -------------- | ------------------------------------------------ |
| `make setup`   | Install deps, create `.env`, detect Tailscale IP |
| `make up`      | Start the stack                                  |
| `make down`    | Stop and remove the container                    |
| `make restart` | Recreate to apply `.env` changes                 |
| `make update`  | Pull the latest image and recreate               |
| `make logs`    | Tail server logs (chromium noise filtered)       |
| `make status`  | Container status                                 |
| `make ip`      | Refresh `TAILSCALE_IP` in `.env`                 |
| `make url`     | Print access URLs + login                        |
| `make open`    | Open the local UI                                |
| `make clean`   | Stop and remove volumes/networks                 |

---

## Why these defaults (hard-won notes)

- **Native arm64 image (GHCR), not Docker Hub.** `m1k1o/neko:chromium` on Docker Hub is
  amd64-only; under emulation on Apple Silicon the VP8 encoder stalls on screen redraw,
  so the view **freezes the moment you click**. The GHCR `ghcr.io/m1k1o/neko/<app>`
  images are native arm64 and smooth.
- **Single UDP+TCP mux port.** A wide ephemeral UDP range is unreliable behind
  OrbStack's userspace networking; one mux port with TCP fallback stays connected.
- **`NAT1TO1` = one IP.** Two IPs of the same candidate type make pion reject the config
  (`invalid address rewrite mapping`) → silent "connection timeout".
- **Object member provider needs every permission set.** In neko, profile flags
  (`can_login`, `can_connect`, `can_watch`, …) default to `false`; the compose file sets
  them explicitly so login works and viewers stay watch-only.
- **Implicit hosting ON + viewer `can_host:false`.** Admin auto-controls on click;
  viewers are rejected by neko before they can grab control.

The hardest bug — the view **freezing on click** — and how it was tracked down is
written up in [docs/POSTMORTEM.md](docs/POSTMORTEM.md).

For installing Insightful safely on the host or on a separate test VM, see
[docs/INSIGHTFUL.md](docs/INSIGHTFUL.md). A minimal UTM VM profile template lives at
[vm/insightful-test.env.example](vm/insightful-test.env.example). There is also an
optional, isolated Docker desktop for installer/browser testing in
[docker-compose.insightful-test.yml](docker-compose.insightful-test.yml); it is run via
[scripts/insightful-test-desktop.sh](scripts/insightful-test-desktop.sh) and does not
change the main neko `Makefile` flow.

---

## Security

- **No public ports.** Access is via `localhost` or your private Tailnet only.
- **Secrets stay local.** `.env` is git-ignored; only `.env.example` (placeholders) is
  committed.
- **Rotate passwords** in `.env`, then `make restart`.

---

## License

MIT
