#!/usr/bin/env bash
# Daily read-only health report for the kit. Never mutates, never prompts.
#
#   FAIL-grade (exit 1): docker daemon unreachable, buildx missing,
#                        docker CLI shadowed by Docker Desktop's injection
#   WARN-grade:          optional pieces - cache registry container,
#                        hub mirror container, mirror registration, systemd
#
# All probes are read-only (docker version/info/ps/system df, systemctl,
# readlink). Run it any time:  ./setup/doctor.sh
set -euo pipefail

KIT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
# shellcheck source=lib/common.sh
source "$KIT_LIB"

kit_require_wsl2

usage() {
  cat <<'USAGE'
Usage: setup/doctor.sh [-h|--help]

Read-only health report for the kit (never mutates, never prompts):
  OK    = healthy      WARN = optional piece missing / misconfigured
  FAIL  = blocking problem (exit 1)

Checks: docker daemon, buildx, active context, systemd, CLI shadowing
(Docker Desktop injection), cache registry + hub mirror containers,
mirror registration, docker disk usage.
USAGE
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    *) warn "Unknown option: $arg (doctor is read-only - no flags besides -h)"; usage >&2; exit 2 ;;
  esac
done

ok()  { printf '  OK    %s\n' "$*"; }
info() { printf '  INFO  %s\n' "$*"; }
warn() { printf '  WARN  %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; }
FAILS=0
WARNS=0
fail()  { bad "$*"; FAILS=$((FAILS + 1)); }
warnc() { warn "$*"; WARNS=$((WARNS + 1)); }

# DI seam (tests): point KIT_DOCKER_CLI_PATH at a controlled docker binary.
CLI_PATH="${KIT_DOCKER_CLI_PATH:-$(command -v docker 2>/dev/null || true)}"

# 1. daemon (rc AND output both matter - a dying daemon can print noise)
if [[ -n "$CLI_PATH" ]]; then
  if server="$(docker version --format '{{.Server.Version}}' 2>/dev/null)" && [[ -n "$server" ]]; then
    ok "docker daemon reachable (server $server)"
  else
    fail "docker daemon unreachable - service off? permission? (docs/faq.md)"
  fi
else
  fail "docker CLI not found - run setup/setup-engine.sh first"
fi

# 2. CLI shadow check: Desktop's WSL integration injects binaries via /mnt/wsl.
CLI_REAL="$(readlink -f "${CLI_PATH:-/nonexistent}" 2>/dev/null || echo n/a)"
if [[ "$CLI_REAL" == *"/mnt/wsl/docker-desktop"* ]]; then
  fail "docker CLI is Desktop's injected binary ($CLI_REAL) - run: ./setup/protect-distro.sh fix"
fi

# 3. buildx
if [[ -n "$(docker buildx version 2>/dev/null || true)" ]]; then
  ok "buildx present ($(docker buildx version 2>/dev/null | awk '{print $2}'))"
else
  fail "buildx missing (docker-buildx-plugin) - cache wrapper needs it"
fi

# 4. active context
ctx="$(docker context show 2>/dev/null || true)"
if [[ -n "$ctx" ]]; then
  ok "docker context: $ctx"
else
  warn "no docker context in use (DOCKER_HOST override active? protect-distro.sh pins 'kit-engine')"
fi

# 5. systemd (docker service persistence)
state="$(systemctl is-system-running 2>/dev/null || true)"
case "$state" in
  running|degraded) ok "systemd: $state" ;;
  *) warnc "systemd not active ($state) - docker service will not persist; enable systemd=true in /etc/wsl.conf + wsl --shutdown" ;;
esac

# 6. cache registry container (optional piece)
reg="$(docker ps --filter name=kit-cache-registry --format '{{.Names}}' 2>/dev/null || true)"
if [[ -n "$reg" ]]; then
  ok "cache registry container up (kit-cache-registry)"
else
  warnc "cache registry not running (optional) - start: docker compose -f cache-stack/docker-compose.registry.yml up -d"
fi

# 7. hub mirror container + daemon registration (optional pieces)
mir="$(docker ps --filter name=kit-hub-mirror --format '{{.Names}}' 2>/dev/null || true)"
if [[ -n "$mir" ]]; then
  ok "hub mirror container up (kit-hub-mirror)"
  if grep -qs '127.0.0.1:5001' <<<"$(docker info 2>/dev/null || true)"; then
    ok "mirror registered in daemon (Registry Mirrors: 127.0.0.1:5001)"
  else
    warnc "mirror runs but is NOT registered in the daemon - set registry-mirrors in daemon.json (docs/registry-mirror.md)"
  fi
else
  warnc "hub mirror not running (optional) - start: docker compose -f cache-stack/docker-compose.mirror.yml up -d"
fi

# 8. disk usage (informational)
df_out="$(docker system df 2>/dev/null || true)"
if [[ -n "$df_out" ]]; then
  info "docker disk usage:"
  printf '%s\n' "$df_out" | sed 's/^/        /'
fi

# --- summary ----------------------------------------------------------------------
if [[ $FAILS -gt 0 ]]; then
  bad "doctor: $FAILS fail, $WARNS warn - fix the FAILs above (docs/faq.md)"
  exit 1
fi
ok "doctor: $FAILS fail, $WARNS warn - critical checks passed"
exit 0
