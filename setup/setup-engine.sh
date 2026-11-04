#!/usr/bin/env bash
# Installs Docker Engine (docker-ce) + buildx + compose plugin inside WSL2.
# Target: Debian/Ubuntu distros with apt. Run as a normal user (asks sudo).
# Reference: https://docs.docker.com/engine/install/ubuntu/
set -euo pipefail

info()  { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }

if [[ $EUID -eq 0 ]]; then
  # Automation escape hatch: KIT_ALLOW_ROOT=1 SUDO_USER=<user> ./setup-engine.sh
  if [[ "${KIT_ALLOW_ROOT:-0}" == "1" ]]; then
    info "Running as root (KIT_ALLOW_ROOT=1); sudo calls are no-ops; target user: ${SUDO_USER:-root}"
  else
    warn "Run this as your normal user (it uses sudo internally), not as root."
    warn "For unattended/automation runs: KIT_ALLOW_ROOT=1 SUDO_USER=<user> $0"
    exit 1
  fi
fi
command -v apt-get >/dev/null || { warn "This script targets Debian/Ubuntu (apt). Adapt docs/setup-wsl2.md for other distros."; exit 1; }

# ext4 guard: builds from /mnt/* are ~5x slower (9P). Fail loudly, don't just warn.
case "$PWD" in
  /mnt/*) warn "You are running from $PWD (Windows drive). Clone the repo inside the distro, e.g. ~/work/, and re-run from there."; exit 1 ;;
esac

info "Installing prerequisites"
sudo apt-get update
sudo apt-get install -y ca-certificates curl

info "Detecting distro for Docker's official apt repository"
# ubuntu and debian have separate repo paths; a hard-coded ubuntu URL 404s on
# Debian (apt-get update would fail) - decide from /etc/os-release.
# shellcheck disable=SC1091  # system file, exists on every apt distro
. /etc/os-release
case "${ID:-}" in
  ubuntu) DOCKER_REPO_PATH="linux/ubuntu" ;;
  debian) DOCKER_REPO_PATH="linux/debian" ;;
  *) warn "Unsupported distro: ${ID:-unknown}. This script supports Ubuntu and Debian."; exit 1 ;;
esac
[ -n "${VERSION_CODENAME:-}" ] || { warn "VERSION_CODENAME missing in /etc/os-release - cannot pick the apt repo."; exit 1; }

info "Adding Docker's official apt repository ($ID / $VERSION_CODENAME)"
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL "https://download.docker.com/$DOCKER_REPO_PATH/gpg" -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/$DOCKER_REPO_PATH $VERSION_CODENAME stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

info "Removing conflicting legacy packages (if any)"
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  sudo apt-get remove -y "$pkg" 2>/dev/null || true
done

info "Installing Docker Engine + buildx + compose plugin"
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

# systemd: needed for the docker service to persist across WSL restarts.
# Judge by the live systemd state, not by parsing /etc/wsl.conf (fragile).
if ! systemctl is-system-running 2>/dev/null | grep -qE '^(running|degraded)$'; then
  if ! grep -qs 'systemd=true' /etc/wsl.conf 2>/dev/null; then
    info "Enabling systemd in /etc/wsl.conf (required for the docker service)"
    printf '\n[boot]\nsystemd=true\n' | sudo tee -a /etc/wsl.conf > /dev/null
    warn "systemd enabled - after this script finishes, run 'wsl --shutdown' from Windows and reopen this terminal."
  fi
fi

if command -v systemctl >/dev/null && systemctl is-system-running >/dev/null 2>&1; then
  info "Enabling and starting the docker service"
  sudo systemctl enable --now docker
else
  warn "systemd not active yet - after 'wsl --shutdown', run: sudo systemctl enable --now docker"
fi

TARGET_USER="${SUDO_USER:-$USER}"
info "Adding '$TARGET_USER' to the docker group"
sudo groupadd docker 2>/dev/null || true
sudo usermod -aG docker "$TARGET_USER"

info "Setup complete."
cat <<'NEXT'

Next steps:
  1. Apply the group membership:  log out & back in, or run:  newgrp docker
  2. Sanity check:                docker version && docker buildx version
  3. Shared cache registry:       docker compose -f cache-stack/docker-compose.registry.yml up -d
  4. Prove the cache loop:        ./setup/verify.sh
  5. Docker Desktop coexists?     Guard this distro:  ./setup/protect-distro.sh check

NEXT
