# Insightful install and test-machine runbook

This repo can make a browser VM reachable over Tailscale, but Insightful is a
native desktop agent. Install it on the **host OS** or on a **real VM guest OS**;
do not expect the neko container itself to appear as a separate Insightful machine.

## Important boundary

If Insightful says the install is **blocked by organization admin**, do not bypass
it. That block is an administrative policy or account entitlement. Resolve it by
using an Insightful organization admin account or asking the org admin to approve
the machine/user/installer.

## Admin-approved install flow

1. Sign in to the Insightful web app as an organization admin:
   - https://app.insightful.io/
2. Confirm the target person/user exists in the organization.
3. Add or invite the user if needed.
4. From the Insightful admin UI, generate/download the desktop app installer for
   the target OS.
5. If your org uses managed deployment, use the admin-provided deployment package
   or install token rather than a public download.
6. On macOS, install the app and grant the permissions requested by the app:
   - Accessibility
   - Screen Recording, if prompted
   - Input Monitoring, if prompted
   - Full Disk Access, only if your org policy requires it
7. Authenticate the desktop app using the org-approved method:
   - employee email login, or
   - invite link, or
   - org/deployment token, depending on how the admin configured the account.
8. In the Insightful dashboard, verify the device appears under the expected user
   and starts reporting activity.

## Session authentication checklist

Use this when installing inside a remote browser/desktop session:

1. Keep the installer and app login inside the same desktop session.
2. Use the user identity assigned by the Insightful admin.
3. Do not reuse one Insightful employee account across several test machines unless
   the admin expects that behavior; duplicate identities can make device attribution
   confusing.
4. Name the OS hostname clearly before installing, for example:
   - `neko-host-macbook`
   - `insightful-test-ubuntu-01`
5. After login, wait several minutes and refresh the Insightful dashboard.
6. If the app says blocked by admin, stop and resolve in the Insightful admin UI;
   reinstalling or changing local files will not fix an org-level block.

## Minimal VM configuration for safety testing

Use a real VM if you need Insightful to detect a separate machine for software
safety testing. A Docker container is not enough because Insightful tracks a native
OS session and device identity.

## Optional Docker desktop for installer/browser testing

If you only need a lightweight browser desktop to exercise the Insightful installer
UI, downloads, login flow, or web dashboard, use the separate Docker config:

```bash
scripts/insightful-test-desktop.sh init
# Put the admin-provided installer in:
#   ./insightful-test/installers
# Edit .env.insightful-test and set INSIGHTFUL_UI_PASSWORD
scripts/insightful-test-desktop.sh up
```

Open:

```text
http://localhost:3010
```

Installer paths:

| Location | Path |
| --- | --- |
| Host Mac | `./insightful-test/installers` |
| Inside desktop | `/config/Downloads/Insightful` |
| Shared artifacts | `./insightful-test/shared` ↔ `/config/Shared` |

This optional desktop is defined in `docker-compose.insightful-test.yml` and uses
`.env.insightful-test`. It does **not** touch the main neko `Makefile` or running
neko stack.

Important: this is still a containerized Linux desktop, not a full hardware VM. It
may be useful for install-flow and browser testing, but if Insightful must be
detected as a separate managed machine, use the UTM VM profile below.

### Recommended Mac setup

Use **UTM** with Apple Virtualization for the cleanest Mac-hosted test VM.

- VM type: Linux VM with GUI
- OS: Ubuntu Desktop LTS
- Architecture:
  - Prefer ARM64 on Apple Silicon for performance.
  - Use AMD64 only if Insightful's Linux agent for your org is AMD64-only.
- CPU: 2 cores
- RAM: 4 GB minimum
- Disk: 32 GB minimum
- Network: shared/NAT is fine; Tailscale inside the guest is optional
- Display: 1280x720 or 1920x1080
- Hostname: `insightful-test-ubuntu-01`
- User: a non-admin daily user, with sudo available only for setup

### Ubuntu guest preparation

Inside the VM:

```bash
sudo hostnamectl set-hostname insightful-test-ubuntu-01
sudo apt update
sudo apt install -y curl ca-certificates xdg-utils gnome-shell-extension-appindicator
```

Then install Insightful using the **admin-provided** Linux package or invite flow.
Do not download random agent binaries from untrusted mirrors.

### Verification

After install and login:

```bash
hostnamectl
whoami
ip addr show
```

In the Insightful dashboard, verify:

- machine name matches `insightful-test-ubuntu-01`
- assigned user is the intended test user
- activity starts appearing after a few minutes

## Why not install it in neko?

The neko container is an application container running Chromium plus a virtual X
display. It is not a normal managed endpoint. Insightful may not see it as a stable
machine identity, and even if the agent starts, the telemetry will not represent a
real desktop endpoint. For valid safety testing, use a host OS or a full VM guest.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Blocked by organization admin | Org policy, missing user, disabled installer, wrong invite | Ask org admin to enable/invite/generate installer |
| App installs but no data | Not logged in, wrong user, missing permissions | Log in again and grant OS permissions |
| VM not detected as separate machine | Installed in container or reused same device identity | Use a full VM with unique hostname and fresh install |
| macOS prompts never appear | App lacks permission prompt/reset state | System Settings > Privacy & Security; remove/re-add app permissions |
| Remote session works but agent sees only host | Installed on host, not guest | Install agent inside the guest VM if you need a separate machine |
