#!/usr/bin/env bash
# Removes everything the kit's setup scripts installed - the mirror of the
# SECURITY.md touch table, in reverse-safe order:
#   containers down -> contexts rm -> bridge drop-in rm -> services off ->
#   group out -> packages purge -> apt repo files rm -> optional .wslconfig restore
#
# Kit-wide mutation policy: --dry-run / KIT_DRY_RUN=1 previews every reversal
# without executing; --yes / KIT_YES=1 runs unattended.
#
# Data safety: /var/lib/docker (image/layer data) and %USERPROFILE%\.wslconfig
# are NEVER touched unless --purge-data / --restore-wslconfig is passed.
# wsl.conf's systemd=true is left in place (harmless; removing it would only
# break other services that now rely on it).
set -euo pipefail

KIT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
# shellcheck source=lib/common.sh
source "$KIT_LIB"

kit_require_wsl2

# --- flags ---------------------------------------------------------------------
usage() {
  cat <<'USAGE'
Usage: setup/teardown.sh [--dry-run] [--yes] [--purge-data] [--restore-wslconfig] [-h|--help]

  --dry-run             preview every reversal, change nothing (alias: KIT_DRY_RUN=1)
  --yes                 no consent prompt - unattended runs (alias: KIT_YES=1)
  --purge-data          ALSO delete the docker data root /var/lib/docker (image/layer data!)
  --restore-wslconfig   restore the newest %USERPROFILE%\.wslconfig.bak.* written by setup-wsl.ps1
  -h, --help            this text

Default behavior: docker data root and .wslconfig are LEFT in place.
Resources that pre-existed the kit are kept (ownership record:
/var/lib/stoke/ownership.env, written by setup-engine.sh).
The WSL distro itself (and your sources in ~/work) is never touched.
USAGE
}

KIT_DRY_RUN="${KIT_DRY_RUN:-0}"
KIT_YES="${KIT_YES:-0}"
PURGE_DATA=0
RESTORE_WSLCONFIG=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)            KIT_DRY_RUN=1 ;;
    --yes)                KIT_YES=1 ;;
    --purge-data)         PURGE_DATA=1 ;;
    --restore-wslconfig)  RESTORE_WSLCONFIG=1 ;;
    -h|--help)            usage; exit 0 ;;
    *) warn "Unknown option: $arg"; usage >&2; exit 2 ;;
  esac
done
export KIT_DRY_RUN KIT_YES

if [[ $EUID -eq 0 ]]; then
  if [[ "${KIT_ALLOW_ROOT:-0}" == "1" ]]; then
    info "Running as root (KIT_ALLOW_ROOT=1); sudo calls are no-ops; target user: ${SUDO_USER:-root}"
  else
    warn "Run this as your normal user (it uses sudo internally), not as root."
    warn "For unattended/automation runs: KIT_ALLOW_ROOT=1 SUDO_USER=<user> $0"
    exit 1
  fi
fi

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"

TARGET_USER="${SUDO_USER:-${USER:-}}"
if [[ -z "$TARGET_USER" ]]; then
  TARGET_USER="$(id -un 2>/dev/null || true)"
fi
[[ -n "$TARGET_USER" ]] || { warn "Cannot determine the invoking user (SUDO_USER/USER/id all unavailable)."; exit 1; }

# setup-wsl.ps1 backs up %USERPROFILE%\.wslconfig (Windows side). Resolve that
# profile through WSL interop; fall back to $HOME when interop is unavailable.
kit_wslconfig_default() {
  local win_home=""
  if command -v cmd.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
    win_home="$(wslpath -u "$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')" 2>/dev/null || true)"
  fi
  printf '%s\n' "${win_home:+$win_home/.wslconfig}"
}
WSLCONFIG="${KIT_WSLCONFIG:-$(kit_wslconfig_default)}"
WSLCONFIG="${WSLCONFIG:-${HOME:-/root}/.wslconfig}"
DATA_ROOT="${KIT_DOCKER_DATA_ROOT:-/var/lib/docker}"
TCP_DROPIN="${KIT_TCP_DROPIN:-/etc/systemd/system/docker.service.d/kit-tcp.conf}"
STATE_DIR="${KIT_STATE_DIR:-/var/lib/stoke}"
OWNERSHIP="$STATE_DIR/ownership.env"
APT_LIST="${KIT_APT_LIST:-/etc/apt/sources.list.d/docker.list}"
APT_KEYRING="${KIT_APT_KEYRING:-/etc/apt/keyrings/docker.asc}"

# --- ownership: reverse ONLY what the kit created -------------------------------
# setup-engine.sh snapshots the pre-install state into ownership.env. Defaults
# are full reversal (OWN_*=1) for installs that predate ownership tracking.
# The record is parsed by allowlist - never sourced/eval'd.
OWN_DOCKER_CE=1; OWN_GROUP=1; OWN_USER=1; OWN_APT_REPO=1
LEGACY_REMOVED=""
if [[ -f "$OWNERSHIP" ]]; then
  while IFS='=' read -r key val; do
    case "$key" in
      DOCKER_CE_PRESENT) [[ "$val" == 1 ]] && OWN_DOCKER_CE=0 ;;
      GROUP_PRESENT)     [[ "$val" == 1 ]] && OWN_GROUP=0 ;;
      USER_IN_GROUP)     [[ "$val" == 1 ]] && OWN_USER=0 ;;
      APT_REPO_PRESENT)  [[ "$val" == 1 ]] && OWN_APT_REPO=0 ;;
      LEGACY_PRESENT)    LEGACY_REMOVED="$val" ;;
    esac
  done < "$OWNERSHIP"
else
  warn "No ownership record at $OWNERSHIP - full reversal (install predates ownership tracking)"
fi

# --- plan + consent ---------------------------------------------------------------
kit_consent "teardown plan (user: $TARGET_USER):
  - containers: compose down for cache-stack (registry + mirror)
  - docker: remove context 'kit-engine'
  - bridge: remove kit-tcp.conf drop-in + Windows 'kit-wsl' context (if present)
  - systemd: disable docker + docker.socket
  - group: remove $TARGET_USER from docker, delete the group (only if kit-created)
  - apt: purge docker-ce, CLI, containerd.io, buildx, compose plugin (only if kit-installed)
  - files: remove $APT_LIST + $APT_KEYRING (only if kit-added)
  KEPT unless flagged: docker data root, .wslconfig, wsl.conf systemd=true"

# 1. containers (needs a reachable engine; harmless if already gone)
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  kit_run docker compose -f cache-stack/docker-compose.registry.yml down 2>/dev/null || true
  kit_run docker compose -f cache-stack/docker-compose.mirror.yml down 2>/dev/null || true
else
  info "docker unreachable - skipping container cleanup (nothing should be running)"
fi

# 2. the kit's pinned client context
kit_run docker context rm -f kit-engine 2>/dev/null || true

# 2b. windows-context bridge remnants, only if the bridge was applied.
# The drop-in lives in the distro; the 'kit-wsl' context lives on WINDOWS,
# reachable through interop (docker.exe) when a Windows CLI is installed.
if [[ -f "$TCP_DROPIN" ]]; then
  kit_run sudo rm -f "$TCP_DROPIN"
  kit_run sudo systemctl daemon-reload
  if command -v docker.exe >/dev/null 2>&1; then
    kit_run docker.exe context rm -f kit-wsl 2>/dev/null || true
  else
    warn "Windows-side context 'kit-wsl' may remain - run setup/windows-context.ps1 -Undo on Windows"
  fi
fi

# 3. services
kit_run sudo systemctl disable --now docker docker.socket 2>/dev/null || true

# 4. group (only what the kit created)
if [[ "$OWN_USER" == 1 ]]; then
  kit_run sudo gpasswd -d "$TARGET_USER" docker 2>/dev/null || true
fi
if [[ "$OWN_GROUP" == 1 ]]; then
  kit_run sudo groupdel docker 2>/dev/null || true
fi

# 5. packages (only if the kit installed them)
if [[ "$OWN_DOCKER_CE" == 1 ]]; then
  kit_run sudo apt-get purge -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
else
  info "Docker Engine pre-existed the kit - keeping the packages"
fi

# 6. apt repo + keyring (only if the kit added them)
if [[ "$OWN_APT_REPO" == 1 ]]; then
  kit_run sudo rm -f "$APT_LIST" "$APT_KEYRING"
fi
if [[ -n "$LEGACY_REMOVED" ]]; then
  info "Setup removed pre-existing legacy packages: $LEGACY_REMOVED"
  info "Restore them manually if needed: sudo apt-get install $LEGACY_REMOVED"
fi

# 7. optional: .wslconfig restore
if [[ "$RESTORE_WSLCONFIG" == "1" ]]; then
  # ls over find on purpose: backup names are kit-generated (timestamp suffix)
  # and the glob keeps this readable. shellcheck: SC2012 accepted.
  # shellcheck disable=SC2012
  newest="$(ls -1 "$WSLCONFIG".bak.* 2>/dev/null | sort | tail -1 || true)"
  if [[ -n "$newest" ]]; then
    kit_run cp "$newest" "$WSLCONFIG"
    info "Restored $WSLCONFIG from $(basename "$newest")"
  else
    warn "$WSLCONFIG: no backup found - leaving the file as is"
  fi
else
  info "Keeping $WSLCONFIG - pass --restore-wslconfig to restore the pre-kit backup"
fi

# 8. optional: docker data root
if [[ -d "$DATA_ROOT" ]]; then
  size="$(du -sh "$DATA_ROOT" 2>/dev/null | awk '{print $1}')"
  if [[ "$PURGE_DATA" == "1" ]]; then
    kit_run sudo rm -rf "$DATA_ROOT"
  else
    info "Keeping $DATA_ROOT (${size:-size unknown}) - pass --purge-data to remove it too"
  fi
else
  info "No docker data root at $DATA_ROOT - nothing to clean there"
fi

# 9. reports (left-in-place artifacts)
if grep -qs 'systemd=true' /etc/wsl.conf 2>/dev/null; then
  info "Note: /etc/wsl.conf still has systemd=true - left in place (harmless)"
fi
for f in /usr/local/bin/nerdctl /usr/local/bin/buildctl /usr/local/bin/buildkitd; do
  if [[ -e "$f" ]]; then
    warn "nerdctl-variant artifact still present: $f (remove manually - teardown reverses only the Docker Engine path)"
  fi
done

# 10. the kit's ownership record - removed only when the kit's install was
# reversed. If the engine pre-existed (and was kept), the record stays: it
# still describes the true pre-kit state for any future run.
if [[ "$OWN_DOCKER_CE" == 1 ]]; then
  kit_run sudo rm -f "$OWNERSHIP"
  kit_run sudo rmdir "$STATE_DIR" 2>/dev/null || true
fi

if kit_is_dry_run; then
  kit_dry_run_footer
  exit 0
fi

info "Teardown complete. The distro itself (and your sources in ~/work) is untouched."
info "Nuclear option (deletes the whole distro) is NOT automated: wsl --unregister <distro> - only if you truly mean it."
