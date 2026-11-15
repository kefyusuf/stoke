#!/usr/bin/env bash
# Project scaffolder: copies a stack template + the cache-aware build
# wrappers into a fresh project dir and writes a project-scoped .env, so
# two projects never share one cache ref by accident.
#
# Usage: setup/init-project.sh <stack> <name> [target-dir]
#   stacks: rust | go | node-ts
#
# Kit mutation policy applies: --dry-run previews, consent gate before
# creation, --yes / KIT_YES=1 unattended.
set -euo pipefail

KIT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
# shellcheck source=lib/common.sh
source "$KIT_LIB"

kit_require_wsl2

usage() {
  cat <<'USAGE'
Usage: setup/init-project.sh <stack> <name> [target-dir]

  stack:  rust | go | node-ts
  name:   project name (registry-safe: [A-Za-z0-9][A-Za-z0-9._-]*)
          used verbatim in .env: CACHE_REF=127.0.0.1:5000/<name>:buildcache

Copies templates/<stack>/ + templates/build.sh + build.ps1 into the
target dir and writes .env there.
USAGE
}

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

KIT_DRY_RUN="${KIT_DRY_RUN:-0}"
KIT_YES="${KIT_YES:-0}"
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) KIT_DRY_RUN=1 ;;
    --yes)     KIT_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done
export KIT_DRY_RUN KIT_YES

stack="${POSITIONAL[0]:-}"
name="${POSITIONAL[1]:-}"
target="${POSITIONAL[2]:-./${name:-}}"
if [[ -z "$stack" || -z "$name" ]]; then
  warn "Both <stack> and <name> are required."
  usage >&2
  exit 2
fi
case "$stack" in
  rust|go|node-ts) : ;;
  *) warn "Unknown stack: $stack"; usage >&2; exit 2 ;;
esac
if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  warn "Invalid project name: $name (use [A-Za-z0-9][A-Za-z0.9._-]* - it goes into the registry ref)"
  usage >&2
  exit 2
fi
if [[ ! -d "$KIT_ROOT/templates/$stack" ]]; then
  warn "Template dir missing: $KIT_ROOT/templates/$stack"
  exit 1
fi

# Refuse to clobber: target must not exist or must be empty.
if [[ -e "$target" && -n "$(ls -A "$target" 2>/dev/null || true)" ]]; then
  warn "Refusing: target exists and is not empty: $target"
  exit 1
fi

kit_consent "init-project plan ($stack -> $target):
  - create $target
  - copy templates/$stack (Dockerfile, compose, sources, .dockerignore, README)
  - copy templates/build.sh + templates/build.ps1 (cache-aware wrappers)
  - write .env: CACHE_REF=127.0.0.1:5000/$name:buildcache
                IMAGE=127.0.0.1:5000/$name:latest"

kit_run mkdir -p "$target"
kit_run cp -r "$KIT_ROOT/templates/$stack/." "$target/"
kit_run cp "$KIT_ROOT/templates/build.sh" "$KIT_ROOT/templates/build.ps1" "$target/"
# Herestring (not a pipe) - dry-run's kit_run does not read stdin.
kit_run tee "$target/.env" > /dev/null <<< "CACHE_REF=127.0.0.1:5000/$name:buildcache
IMAGE=127.0.0.1:5000/$name:latest"
kit_run chmod +x "$target/build.sh"

if kit_is_dry_run; then
  kit_dry_run_footer
  exit 0
fi

info "Project '$name' ($stack) initialized at $target"
cat <<'NEXT'

Next steps:
  1. cd into the project
  2. ./build.sh            # cache-aware build; CACHE_REF already in .env
  3. docker compose -f docker-compose.yml --profile dev up   # dev server
  4. ./setup/doctor.sh (from the kit) for the daily health report

NEXT
