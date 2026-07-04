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

echo "Waiting for $CONTAINER..."
for _ in {1..60}; do
  if docker exec "$CONTAINER" sh -lc 'test -f /etc/os-release' >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

docker exec "$CONTAINER" bash -lc '
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
Place the org-admin-provided installer there from the host path:
  ./insightful-test/installers
Supported: .deb, .AppImage, .sh
MSG
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

cat > /config/Desktop/Install-Insightful.desktop <<"INNER"
[Desktop Entry]
Type=Application
Name=Install Insightful
Comment=Install org-admin-provided Insightful package from /config/Downloads/Insightful
Exec=mate-terminal -- bash -lc '/config/Shared/install-insightful.sh; echo; read -p "Press Enter to close..."'
Terminal=false
Categories=Utility;
INNER
chmod +x /config/Desktop/Install-Insightful.desktop

apt-get clean
rm -rf /var/lib/apt/lists/*
'

echo "Installed terminal tools and helpers."
echo "Inside desktop:"
echo "  /config/Shared/workvm-info.sh"
echo "  /config/Shared/install-insightful.sh"
echo "  Desktop shortcut: Install Insightful"
