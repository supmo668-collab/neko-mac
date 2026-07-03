# Post-mortem: the "freeze on click" bug

The single hardest bug in building this stack. Writing it down so the next person
(or the next me) doesn't lose an evening to it.

## Symptom

Everything looked healthy:

- The container started cleanly and reported `neko ready`.
- The web UI loaded over both `localhost` and the Tailscale IP.
- Login succeeded; the **remote browser video rendered fine**.
- The mouse cursor even **moved** across the screen.

Then, **the instant you clicked, the view froze indefinitely.** No error dialog, no
crash — the stream just stopped updating. Reconnecting worked, but the next click froze
it again.

## Why it was hard

The failure had several misleading properties:

1. **It looked like a control/permissions problem.** The freeze coincided with the exact
   moment control is granted, so every early theory pointed at neko's hosting/permission
   model (implicit hosting, control locks, session collisions). Those were all real
   rabbit holes that produced *other* bugs and fixes but never touched the freeze.
2. **Server logs blamed the client.** At freeze time the server logged
   `websocket: close 1001 (going away)` — which is the code a browser sends when a tab
   navigates or closes. That framed it as a client-side action, when it was actually the
   client reacting to a stalled media stream (or the user reloading the frozen tab).
3. **CPU looked idle.** `docker stats` showed **0.82% CPU** during the freeze. That
   seemingly ruled out "the encoder is overloaded" — the exact opposite of the truth.
4. **A config red herring.** Mixing V2 and V3 environment variables had forced neko into
   a legacy compatibility mode with a websocket proxy. That was a plausible-looking
   culprit and consumed a full detour (including a wrong "disable legacy mode" attempt
   that broke the client entirely, because the bundled client needs the legacy `/ws`
   endpoint).

## Root cause

The image we started from — `m1k1o/neko:chromium` on **Docker Hub** — is **amd64-only**.
On an Apple Silicon Mac it therefore ran under **QEMU emulation** (via OrbStack's
`platform: linux/amd64`).

neko captures the screen with a GStreamer pipeline and encodes it with **VP8**
(`vp8enc`, multi-threaded, real-time deadline). Under emulation, when the screen content
changed suddenly — which is exactly what a **click** triggers (page repaint) — the
emulated encoder pipeline **stalled** instead of keeping up. The media flow halted, the
WebRTC connection went stale, and the client eventually tore down the WebSocket.

The "0.82% CPU" was the tell we misread: the emulated encoder thread was **stalled/
blocked**, not spinning — so host CPU stayed low while the pipeline was effectively
wedged. Mouse *movement* survived because it barely changes the framebuffer; a *click*
that repaints the page is what tipped the emulated encoder over.

## The fix

Switch to the **native arm64** image published on GHCR:

```yaml
# before (Docker Hub, amd64-only → emulated → freezes on click)
image: m1k1o/neko:chromium
platform: linux/amd64

# after (GHCR, native arm64 → no emulation → smooth)
image: ghcr.io/m1k1o/neko/chromium:latest
```

Verified native with `docker exec … uname -m` → `aarch64`. Interaction became smooth
immediately.

## Lessons

- **On Apple Silicon, check the image architecture first.** `docker exec <c> uname -m`
  should say `aarch64`. If a container needs `platform: linux/amd64`, treat emulation as
  a prime suspect for any real-time media / CPU-timing weirdness.
- **Idle CPU does not exonerate the encoder.** A *stalled* emulated thread reads as low
  CPU. Judge media health by frame flow, not `docker stats` alone.
- **`websocket: close 1001` is a symptom, not a cause.** It often means the client left a
  page that had already broken — look upstream at the media path.
- **Fix one variable at a time.** Several unrelated fixes (mux port, NAT1TO1, member
  permissions, hosting model) were genuinely necessary but masked the freeze. Isolating
  the freeze from those took discipline.

## The other (smaller) bugs found along the way

These were real and are baked into the current config:

- **`NAT1TO1` must be a single IP.** Two IPs of the same ICE candidate type make pion
  reject the mapping (`invalid address rewrite mapping`) → silent connection timeout.
- **The object member provider needs every permission flag set.** neko's `MemberProfile`
  booleans default to `false`; unset flags mean "Unauthorized" or a watch-only admin.
- **One session per username.** Two logins with the same admin username ping-pong the
  single host slot ("X took over control"). One admin login; everyone else is a viewer.
- **Wide UDP port ranges are flaky under OrbStack.** A single UDP+TCP mux port with TCP
  fallback is far more reliable behind macOS userspace networking.
