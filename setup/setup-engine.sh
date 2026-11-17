#!/usr/bin/env bash
# Installs Docker Engine (docker-ce) + buildx + compose plugin inside WSL2.
# Target: Debian/Ubuntu distros with apt. Run as a normal user (asks sudo).
# Reference: https://docs.docker.com/engine/install/ubuntu/
#
# Kit-wide mutation policy:
#   ./setup/setup-engine.sh            # consent prompt before any change
#   --dry-run / KIT_DRY_RUN=1          # print every change, execute nothing
#   --yes     / KIT_YES=1              # unattended (no prompt)
set -euo pipefail

KIT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
# shellcheck source=lib/common.sh
source "$KIT_LIB"

kit_require_wsl2

# --- flags ---------------------------------------------------------------------
usage() {
  cat <<'USAGE'
Usage: setup/setup-engine.sh [--dry-run] [--yes] [-h|--help]

  --dry-run   print every change, execute nothing   (alias: KIT_DRY_RUN=1)
  --yes       no consent prompt - unattended runs   (alias: KIT_YES=1)
  -h, --help  this text

Other kit guards: refuses WSL1/non-WSL hosts (KIT_ALLOW_LINUX=1 override),
refuses /mnt/* working dirs, refuses root without KIT_ALLOW_ROOT=1 SUDO_USER=...
USAGE
}

KIT_DRY_RUN="${KIT_DRY_RUN:-0}"
KIT_YES="${KIT_YES:-0}"
for arg in "$@"; do
  case "$arg" in
    --dry-run) KIT_DRY_RUN=1 ;;
    --yes)     KIT_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) warn "Unknown option: $arg"; usage >&2; exit 2 ;;
  esac
done
export KIT_DRY_RUN KIT_YES

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

info "Detecting distro for Docker's official apt repository"
# ubuntu and debian have separate repo paths; a hard-coded ubuntu URL 404s on
# Debian (apt-get update would fail) - decide from os-release.
OS_RELEASE_FILE="${KIT_OS_RELEASE_FILE:-/etc/os-release}"
# shellcheck disable=SC1090
. "$OS_RELEASE_FILE"
case "${ID:-}" in
  ubuntu) DOCKER_REPO_PATH="linux/ubuntu" ;;
  debian) DOCKER_REPO_PATH="linux/debian" ;;
  *) warn "Unsupported distro: ${ID:-unknown}. This script supports Ubuntu and Debian."; exit 1 ;;
esac
[ -n "${VERSION_CODENAME:-}" ] || { warn "VERSION_CODENAME missing in $OS_RELEASE_FILE - cannot pick the apt repo."; exit 1; }

TARGET_USER="${SUDO_USER:-${USER:-}}"
if [[ -z "$TARGET_USER" ]]; then
  TARGET_USER="$(id -un 2>/dev/null || true)"
fi
[[ -n "$TARGET_USER" ]] || { warn "Cannot determine the invoking user (SUDO_USER/USER/id all unavailable)."; exit 1; }

# --- ownership snapshot (read-only probes, before any mutation) ------------------
# Records what pre-existed so teardown reverses ONLY what the kit created.
STATE_DIR="${KIT_STATE_DIR:-/var/lib/stoke}"
OWNERSHIP="$STATE_DIR/ownership.env"
APT_LIST="${KIT_APT_LIST:-/etc/apt/sources.list.d/docker.list}"
APT_KEYRING="${KIT_APT_KEYRING:-/etc/apt/keyrings/docker.asc}"

kit_pkg_installed() {
  [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null || true)" == *"install ok installed"* ]]
}

DOCKER_CE_PRESENT=0; kit_pkg_installed docker-ce && DOCKER_CE_PRESENT=1
GROUP_PRESENT=0; getent group docker >/dev/null 2>&1 && GROUP_PRESENT=1
USER_IN_GROUP=0
[[ " $(id -nG "$TARGET_USER" 2>/dev/null || true) " == *" docker "* ]] && USER_IN_GROUP=1
APT_REPO_PRESENT=0
[[ -f "$APT_LIST" || -f "$APT_KEYRING" ]] && APT_REPO_PRESENT=1
LEGACY_PRESENT=""
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  kit_pkg_installed "$pkg" && LEGACY_PRESENT="${LEGACY_PRESENT:+$LEGACY_PRESENT }$pkg"
done
WSLCONF_SYSTEMD=0; grep -qs 'systemd=true' /etc/wsl.conf 2>/dev/null && WSLCONF_SYSTEMD=1

# --- plan + consent ---------------------------------------------------------------
if [[ "$DOCKER_CE_PRESENT" == 1 ]]; then
  kit_consent "setup-engine plan (distro: $ID/$VERSION_CODENAME):
  - existing Docker Engine detected - REUSING it (no package changes)
  - ownership: record pre-install state in $OWNERSHIP (if no record yet)
  - systemd: enable docker.service (writes systemd=true into /etc/wsl.conf only if needed)
  - group: ensure 'docker' group and '$TARGET_USER' membership"
else
  kit_consent "setup-engine plan (distro: $ID/$VERSION_CODENAME):
  - ownership: record pre-install state in $OWNERSHIP
  - apt: add Docker's official repo ($APT_KEYRING, $APT_LIST)
  - apt: remove conflicting legacy packages (docker.io, docker-doc, docker-compose, podman-docker, containerd, runc)
  - apt: install docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin, docker-compose-plugin
  - systemd: enable docker.service (writes systemd=true into /etc/wsl.conf only if needed)
  - group: create 'docker' and add '$TARGET_USER' to it"
fi

# The ownership record is the first mutation; a re-run never overwrites the
# original snapshot (it describes the state before the FIRST kit install).
if [[ -f "$OWNERSHIP" ]]; then
  info "Ownership record exists ($OWNERSHIP) - keeping the original snapshot"
else
  manifest="KIT_OWNERSHIP_VERSION=1
DOCKER_CE_PRESENT=$DOCKER_CE_PRESENT
GROUP_PRESENT=$GROUP_PRESENT
USER_IN_GROUP=$USER_IN_GROUP
APT_REPO_PRESENT=$APT_REPO_PRESENT
LEGACY_PRESENT=$LEGACY_PRESENT
WSLCONF_SYSTEMD=$WSLCONF_SYSTEMD"
  kit_run sudo install -m 0755 -d "$STATE_DIR"
  kit_run sudo tee "$OWNERSHIP" > /dev/null <<< "$manifest"
fi

if [[ "$DOCKER_CE_PRESENT" == 1 ]]; then
  info "Existing Docker Engine detected - reusing it (no package changes)"
else
  info "Installing prerequisites"
  kit_run sudo apt-get update
  kit_run sudo apt-get install -y ca-certificates curl

  info "Adding Docker's official apt repository ($ID / $VERSION_CODENAME)"
  kit_run sudo install -m 0755 -d /etc/apt/keyrings
  kit_run sudo curl -fsSL "https://download.docker.com/$DOCKER_REPO_PATH/gpg" -o "$APT_KEYRING"
  kit_run sudo chmod a+r "$APT_KEYRING"
  sources_line="deb [arch=$(dpkg --print-architecture) signed-by=$APT_KEYRING] https://download.docker.com/$DOCKER_REPO_PATH $VERSION_CODENAME stable"
  # Herestring (not `echo |`) on purpose: in dry-run the consumer side of
  # kit_run does not read stdin, and a pipe producer would die of SIGPIPE.
  kit_run sudo tee "$APT_LIST" > /dev/null <<< "$sources_line"

  info "Removing conflicting legacy packages (if any)"
  for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    kit_run sudo apt-get remove -y "$pkg" 2>/dev/null || true
  done

  info "Refreshing apt lists (docker repo just added)"
  kit_run sudo apt-get update

  info "Installing Docker Engine + buildx + compose plugin"
  kit_run sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
fi

# systemd: needed for the docker service to persist across WSL restarts.
# Judge by the live systemd state, not by parsing /etc/wsl.conf (fragile).
if ! systemctl is-system-running 2>/dev/null | grep -qE '^(running|degraded)$'; then
  if ! grep -qs 'systemd=true' /etc/wsl.conf 2>/dev/null; then
    info "Enabling systemd in /etc/wsl.conf (required for the docker service)"
    printf '\n[boot]\nsystemd=true\n' | kit_run sudo tee -a /etc/wsl.conf > /dev/null
    warn "systemd enabled - after this script finishes, run 'wsl --shutdown' from Windows and reopen this terminal."
  fi
fi

if command -v systemctl >/dev/null && systemctl is-system-running >/dev/null 2>&1; then
  info "Enabling and starting the docker service"
  kit_run sudo systemctl enable --now docker
else
  warn "systemd not active yet - after 'wsl --shutdown', run: sudo systemctl enable --now docker"
fi

info "Adding '$TARGET_USER' to the docker group"
kit_run sudo groupadd docker 2>/dev/null || true
kit_run sudo usermod -aG docker "$TARGET_USER"

if kit_is_dry_run; then
  kit_dry_run_footer
  exit 0
fi

info "Setup complete."
cat <<'NEXT'

Next steps:
  1. Apply the group membership:  log out & back in, or run:  newgrp docker
  2. Sanity check:                docker version && docker buildx version
  3. Shared cache registry:       docker compose -f cache-stack/docker-compose.registry.yml up -d
  4. Prove the cache loop:        ./setup/verify.sh
  5. Daily health report:         ./setup/doctor.sh
  6. Docker Desktop coexists?     Guard this distro:  ./setup/protect-distro.sh check
  7. Remove everything again:     ./setup/teardown.sh --dry-run first, then without it

NEXT

# Desktop coexistence auto-check (read-only, best-effort): catches the common
# case of Desktop's WSL integration being ON while we installed - the user
# learns immediately instead of on the first weird docker call.
if [[ -x setup/protect-distro.sh ]]; then
  info "Docker Desktop coexistence check:"
  ./setup/protect-distro.sh check || true
fi
