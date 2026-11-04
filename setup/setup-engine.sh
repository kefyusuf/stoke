#!/usr/bin/env bash
# Installs Docker Engine (docker-ce) + buildx + compose plugin inside WSL2.
# Target: Debian/Ubuntu distros with apt. Run as a normal user (asks sudo).
# Reference: https://docs.docker.com/engine/install/ubuntu/
set -euo pipefail

info()  { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }

[[ $EUID -eq 0 ]] && { warn "Run this as your normal user (it uses sudo internally), not as root."; exit 1; }
command -v apt-get >/dev/null || { warn "This script targets Debian/Ubuntu (apt). Adapt docs/setup-wsl2.md for other distros."; exit 1; }

# ext4 guard: builds from /mnt/* are ~5x slower (9P). Fail loudly, don't just warn.
case "$PWD" in
  /mnt/*) warn "You are running from $PWD (Windows drive). Clone the repo inside the distro, e.g. ~/work/, and re-run from there."; exit 1 ;;
esac

info "Installing prerequisites"
sudo apt-get update
sudo apt-get install -y ca-certificates curl

info "Adding Docker's official apt repository"
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "${VERSION_CODENAME:-noble}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

info "Removing conflicting legacy packages (if any)"
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  sudo apt-get remove -y "$pkg" 2>/dev/null || true
done

info "Installing Docker Engine + buildx + compose plugin"
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

# systemd: needed for `systemctl enable --now docker` to persist across WSL restarts.
if grep -qs '^\[boot\]' /etc/wsl.conf && ! grep -qsA1 '^\[boot\]' /etc/wsl.conf | grep -qs 'systemd=true'; then
  warn "/etc/wsl.conf has [boot] but systemd is not enabled - add 'systemd=true' under [boot], then 'wsl --shutdown'."
elif ! grep -qs '^\[boot\]' /etc/wsl.conf; then
  info "Enabling systemd in /etc/wsl.conf (required for the docker service)"
  printf '\n[boot]\nsystemd=true\n' | sudo tee -a /etc/wsl.conf > /dev/null
  warn "systemd enabled - after this script finishes, run 'wsl --shutdown' from Windows and reopen this terminal."
fi

if command -v systemctl >/dev/null && systemctl is-system-running >/dev/null 2>&1; then
  info "Enabling and starting the docker service"
  sudo systemctl enable --now docker
else
  warn "systemd not active yet - after 'wsl --shutdown', run: sudo systemctl enable --now docker"
fi

info "Adding '$USER' to the docker group"
sudo groupadd docker 2>/dev/null || true
sudo usermod -aG docker "$USER"

info "Setup complete."
cat <<'NEXT'

Next steps:
  1. Apply the group membership:  log out & back in, or run:  newgrp docker
  2. Sanity check:                docker version && docker buildx version
  3. Shared cache registry:       docker compose -f cache-stack/docker-compose.registry.yml up -d
  4. Prove the cache loop:        ./setup/verify.sh

NEXT
