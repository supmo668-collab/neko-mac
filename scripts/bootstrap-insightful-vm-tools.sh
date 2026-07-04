#!/usr/bin/env bash
# Install basic terminal/installer tools inside the optional Insightful test desktop.
# This does not touch the main neko stack.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env.insightful-test"
COMPOSE_FILE="$ROOT_DIR/docker-compose.insightful-test.yml"
SERVICE="insightful-test-desktop"
CONTAINER="insightful-test-desktop"

if [ ! -f "$ENV_FILE" ]; then
  echo "No .env.insightful-test found. Run: scripts/insightful-test-desktop.sh init" >&2
  exit 1
fi

cd "$ROOT_DIR"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d

desktop_exec() {
  docker exec "$CONTAINER" "$@" 2> >(grep -v 'Failed to create stream fd' >&2)
}

echo "Waiting for $CONTAINER..."
for _ in {1..60}; do
  if desktop_exec sh -lc 'test -f /etc/os-release' >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

desktop_exec bash -lc '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  apt-transport-https \
  ca-certificates \
  curl \
  wget \
  gnupg \
  lsb-release \
  software-properties-common \
  gdebi-core \
  unzip \
  xz-utils \
  zip \
  file \
  jq \
  less \
  nano \
  vim-tiny \
  htop \
  procps \
  psmisc \
  lsof \
  iproute2 \
  iputils-ping \
  net-tools \
  dnsutils \
  traceroute \
  openssl \
  xdg-utils \
  dbus-x11

# Chrome note: Google Chrome for Linux is amd64-only. On Apple Silicon/arm64 webtop,
# Chromium is the correct Chrome-family browser and is already present in this image.
arch="$(dpkg --print-architecture)"
if [ "$arch" = "amd64" ] && ! command -v google-chrome >/dev/null 2>&1; then
  install -d -m 0755 /etc/apt/keyrings
  wget -qO- https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /etc/apt/keyrings/google-linux.gpg
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-linux.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
  apt-get update
  apt-get install -y --no-install-recommends google-chrome-stable
fi

mkdir -p /config/Shared /config/Downloads/Insightful /config/Desktop
cat > /config/Downloads/Insightful/PUT_INSIGHTFUL_INSTALLER_HERE.txt <<"INNER"
Put the org-admin-provided Insightful installer in this folder.

Host Mac path:
  ./insightful-test/installers

Inside this desktop:
  /config/Downloads/Insightful

Supported installer types:
  .deb
  .AppImage
  .sh

After placing the installer here, run one of these inside the desktop:
  install-insightful
  /config/Shared/install-insightful.sh

Or double-click the desktop icon:
  Install Insightful
INNER

cat > /config/Shared/install-insightful.sh <<"INNER"
#!/usr/bin/env bash
set -euo pipefail

INSTALLER_DIR="/config/Downloads/Insightful"
cd "$INSTALLER_DIR"

installer="${1:-}"
if [ -z "$installer" ]; then
  installer="$(find . -maxdepth 1 -type f \( -name "*.deb" -o -name "*.AppImage" -o -name "*.sh" \) | sort | head -1 | sed "s#^./##")"
fi

if [ -z "$installer" ]; then
  cat >&2 <<MSG
No Insightful installer found in $INSTALLER_DIR.
Place the org-admin-provided installer in the host path:
  /Users/hiroshi/vm_setup/insightful-test/installers

It will appear inside this desktop at:
  $INSTALLER_DIR

Supported: .deb, .AppImage, .sh
MSG
  if command -v caja >/dev/null 2>&1; then
    caja "$INSTALLER_DIR" >/dev/null 2>&1 &
  fi
  exit 1
fi

case "$installer" in
  *.deb)
    echo "Installing .deb with apt: $installer"
    apt-get update
    apt-get install -y "./$installer"
    ;;
  *.AppImage)
    echo "Preparing AppImage: $installer"
    chmod +x "$installer"
    echo "Run it with: $INSTALLER_DIR/$installer"
    ;;
  *.sh)
    echo "Running shell installer: $installer"
    chmod +x "$installer"
    "./$installer"
    ;;
  *)
    echo "Unsupported installer: $installer" >&2
    exit 1
    ;;
esac
INNER
chmod +x /config/Shared/install-insightful.sh

cat > /config/Shared/workvm-info.sh <<"INNER"
#!/usr/bin/env bash
set -euo pipefail
cat /etc/os-release
printf "\nhostname: "; hostname
printf "user: "; whoami
printf "arch: "; dpkg --print-architecture
printf "kernel: "; uname -a
printf "\nBrowsers:\n"
for c in google-chrome chromium chromium-browser firefox; do
  if command -v "$c" >/dev/null 2>&1; then
    printf "  %s -> %s\n" "$c" "$(command -v "$c")"
  fi
done
printf "\nInstaller path:\n  /config/Downloads/Insightful\n"
printf "Install helper:\n  /config/Shared/install-insightful.sh\n"
INNER
chmod +x /config/Shared/workvm-info.sh

cat > /config/Shared/open-install-insightful-terminal.sh <<"INNER"
#!/usr/bin/env bash
mate-terminal -- bash -lc "/config/Shared/install-insightful.sh; echo; echo Press Enter to close...; read -r"
INNER
chmod +x /config/Shared/open-install-insightful-terminal.sh

cat > /config/Shared/open-workvm-info-terminal.sh <<"INNER"
#!/usr/bin/env bash
mate-terminal -- bash -lc "/config/Shared/workvm-info.sh; echo; echo Press Enter to close...; read -r"
INNER
chmod +x /config/Shared/open-workvm-info-terminal.sh

cat > /config/Desktop/Install-Insightful.desktop <<"INNER"
[Desktop Entry]
Type=Application
Name=Install Insightful
Comment=Install org-admin-provided Insightful package from /config/Downloads/Insightful
Exec=/config/Shared/open-install-insightful-terminal.sh
Terminal=false
Categories=Utility;
INNER

cat > /config/Desktop/Work-VM-Info.desktop <<"INNER"
[Desktop Entry]
Type=Application
Name=Work VM Info
Comment=Show OS, hostname, architecture, browser, and installer paths
Exec=/config/Shared/open-workvm-info-terminal.sh
Terminal=false
Categories=Utility;
INNER

cat > /config/Desktop/Terminal.desktop <<"INNER"
[Desktop Entry]
Type=Application
Name=Terminal
Comment=Open a terminal in the Insightful test desktop
Exec=mate-terminal
Icon=utilities-terminal
Terminal=false
Categories=System;TerminalEmulator;
INNER

if [ -f /usr/share/applications/chromium.desktop ]; then
  cp /usr/share/applications/chromium.desktop /config/Desktop/Chromium.desktop
else
  cat > /config/Desktop/Chromium.desktop <<"INNER"
[Desktop Entry]
Type=Application
Name=Chromium
Comment=Open the Chromium browser
Exec=chromium %U
Icon=chromium
Terminal=false
Categories=Network;WebBrowser;
INNER
fi

chmod 755 /config/Shared/*.sh /config/Desktop/*.desktop
chown -R abc:abc /config/Shared /config/Downloads/Insightful /config/Desktop
ln -sf /config/Shared/install-insightful.sh /usr/local/bin/install-insightful
ln -sf /config/Shared/workvm-info.sh /usr/local/bin/workvm-info

# MATE/Caja may hide launchers until they are marked trusted. Ignore if gio is absent.
for launcher in /config/Desktop/*.desktop; do
  gio set "$launcher" metadata::trusted true >/dev/null 2>&1 || true
done

apt-get clean
rm -rf /var/lib/apt/lists/*
'

echo "Installed terminal tools and helpers."
echo "Inside desktop:"
echo "  /config/Shared/workvm-info.sh"
echo "  /config/Shared/install-insightful.sh"
echo "  Desktop shortcut: Install Insightful"
