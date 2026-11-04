#!/usr/bin/env bash
# Keeps THIS distro's Docker engine independent from Docker Desktop's WSL
# integration ("injection").
#
# What Desktop's integration does to an integrated distro (all three shadow or
# hijack the kit's engine):
#   1. symlinks /usr/local/bin/docker{,-compose} -> /mnt/wsl/docker-desktop/...
#      (PATH: /usr/local/bin precedes /usr/bin, so it shadows docker-ce's CLI)
#   2. repoints /var/run/docker.sock at its shared socket
#      (so even our CLI talks to Desktop's engine)
#   3. installs a docker-desktop-proxy systemd unit to keep 1+2 in place
#
# Usage:
#   ./setup/protect-distro.sh check     # report who owns CLI + socket (default)
#   ./setup/protect-distro.sh fix       # remove Desktop artifacts, restore our
#                                       # socket, pin default context to it
#                                       # (root/sudo; reversible — see docs/migration.md)
# Exit codes: 0 = clean, 1 = Desktop artifacts detected / fix failed.
set -euo pipefail

info() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m  PASS  %s\033[0m\n' "$*"; }
bad()  { printf '\033[1;31m  FAIL  %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  WARN  %s\033[0m\n' "$*"; }

MODE="${1:-check}"
SOCKET=/var/run/docker.sock
DESKTOP_PATH_MARK="/mnt/wsl/docker-desktop"

failures=0
note_fail() { bad "$*"; failures=$((failures + 1)); }

# --- gather current state ------------------------------------------------------
gather_state() {
  CLI_PATH=$(command -v docker 2>/dev/null || true)
  CLI_REAL=$(readlink -f "${CLI_PATH:-/nonexistent-docker}" 2>/dev/null || echo "n/a")
  SOCKET_LINK=$(readlink "$SOCKET" 2>/dev/null || true)
  DESKTOP_UNITS=$(find /etc/systemd/system -maxdepth 1 -name '*docker-desktop*' -not -type l 2>/dev/null || true)
  DESKTOP_SYMLINKS=""
  if [ -d /usr/local/bin ]; then
    DESKTOP_SYMLINKS=$(find /usr/local/bin -maxdepth 1 \( -name 'docker' -o -name 'docker-compose' -o -name 'docker-credential-*' \) -type l \
      -exec sh -c 'readlink -f "$1" | grep -q "/mnt/wsl/docker-desktop" && echo "$1"' _ {} \; 2>/dev/null || true)
  fi
}
gather_state

report() {
  echo "  CLI          : ${CLI_PATH:-none} -> ${CLI_REAL}"
  echo "  socket       : ${SOCKET} ${SOCKET_LINK:+-> symlink: ${SOCKET_LINK}}"
  [ -z "$DESKTOP_UNITS" ]     || echo "  desktop units: $DESKTOP_UNITS"
  [ -z "$DESKTOP_SYMLINKS" ]  || echo "  desktop symlinks: $DESKTOP_SYMLINKS"
  [ -z "${DOCKER_HOST:-}" ]   || echo "  DOCKER_HOST  : ${DOCKER_HOST} (env override active)"
}

# --- check mode -----------------------------------------------------------------
check() {
  echo "--- distro docker ownership:"
  report
  if [ -z "$CLI_PATH" ]; then
    warn "no docker CLI found in PATH (engine not installed here?)"
  elif [[ "$CLI_REAL" == "$DESKTOP_PATH_MARK"* ]]; then
    note_fail "docker CLI is Docker Desktop's injected binary: $CLI_REAL"
  else
    ok "docker CLI belongs to this distro ($CLI_REAL)"
  fi
  if [[ "$SOCKET_LINK" == *"docker-desktop"* ]]; then
    note_fail "socket hijacked: $SOCKET -> $SOCKET_LINK"
  elif [ -z "$SOCKET_LINK" ] && [ -S "$SOCKET" ]; then
    ok "socket is a real local socket (ours)"
  elif [ -e "$SOCKET" ]; then
    warn "socket is neither ours nor visibly hijacked: $(stat -c '%A %N' "$SOCKET")"
  else
    warn "socket not present (engine not running?)"
  fi
  if [ -n "$DESKTOP_UNITS" ]; then
    note_fail "Desktop integration units present: $(echo "$DESKTOP_UNITS" | sed -e 's|.*/||' | tr '\n' ' ')"
  fi
  if [ -n "$DESKTOP_SYMLINKS" ]; then
    note_fail "Desktop CLI symlinks present: $(echo "$DESKTOP_SYMLINKS" | sed -e 's|.*/||' | tr '\n' ' ')"
  fi
  echo ""
  if [ "$failures" -eq 0 ]; then
    ok "distro is independent from Docker Desktop"
    if [ -n "$CLI_PATH" ] && [[ "$CLI_REAL" != "$DESKTOP_PATH_MARK"* ]]; then
      docker version --format '  server: {{.Server.Version}}' 2>/dev/null \
        || warn "  (daemon not reachable right now)"
    fi
    return 0
  fi
  bad "$failures injection signal(s) - run 'fix' to clean (see docs/migration.md)"
  return 1
}

# --- fix mode --------------------------------------------------------------------
fix() {
  if [[ $EUID -ne 0 ]]; then
    warn "fix needs root: run with sudo, or as root with KIT_ALLOW_ROOT=1 SUDO_USER=<user>"
    exit 1
  fi
  TARGET_USER="${SUDO_USER:-$USER}"

  if [ -n "$DESKTOP_UNITS" ]; then
    for u in $DESKTOP_UNITS; do
      info "neutralizing $(basename "$u") (blocks Desktop from restarting its proxy)"
      systemctl mask --now --force "$(basename "$u")" >/dev/null 2>&1 || true
      # Some systemd builds refuse to overwrite an existing unit file even with
      # --force - do explicitly what mask would have done (reversible: rm the
      # /dev/null symlink, i.e. `systemctl unmask`).
      if [ -f "$u" ]; then
        rm -f "$u"
        ln -s /dev/null "$u"
        systemctl daemon-reload 2>/dev/null || true
      fi
      if [ "$(readlink "$u" 2>/dev/null)" = "/dev/null" ]; then
        ok "$(basename "$u") masked (-> /dev/null)"
      else
        warn "could not neutralize $(basename "$u") (Desktop may restart its proxy)"
      fi
    done
    systemctl daemon-reload 2>/dev/null || true
  fi

  if [ -n "$DESKTOP_SYMLINKS" ]; then
    info "removing Desktop CLI symlinks"
    while IFS= read -r f; do rm -f "$f"; done <<< "$DESKTOP_SYMLINKS"
  fi

  if [[ "$SOCKET_LINK" == *"docker-desktop"* ]]; then
    info "restoring local socket via our docker.socket"
    systemctl restart docker.socket docker 2>/dev/null || systemctl restart docker || true
  fi

  # Belt & suspenders: pin the default docker CONTEXT to the local socket for
  # the target user, so even a re-injected Desktop CLI talks to OUR engine
  # (contexts are client-side and shared across CLI binaries).
  if [ -S "$SOCKET" ] && [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ]; then
    if sudo -u "$TARGET_USER" -H docker context inspect kit-engine >/dev/null 2>&1; then
      info "context 'kit-engine' already exists for $TARGET_USER"
    else
      info "creating context 'kit-engine' (pinned to $SOCKET) for $TARGET_USER"
      sudo -u "$TARGET_USER" -H docker context create kit-engine --docker "host=unix://${SOCKET}" >/dev/null
    fi
    sudo -u "$TARGET_USER" -H docker context use kit-engine >/dev/null
    ok "default context pinned to the kit engine for $TARGET_USER"
  fi

  # Re-evaluate state and report.
  gather_state
  echo ""
  check || true
  info "Note: 'fix' is reversible — if you WANT Desktop's engine in this distro,"
  info "re-enable WSL Integration in Desktop settings and: systemctl unmask <unit>."
}

case "$MODE" in
  check) check ;;
  fix)   fix ;;
  *)     warn "usage: $0 [check|fix]"; exit 2 ;;
esac
