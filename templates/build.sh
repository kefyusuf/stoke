#!/usr/bin/env bash
# Cache-aware buildx wrapper (Linux / WSL2). Windows twin: build.ps1.
#
# Usage (from your project root, Dockerfile in place):
#   ./build.sh                          # CACHE_REF from .env or dir-name default
#   ./build.sh -- --platform linux/arm64  # extra buildx args pass through
#   CACHE_REF=ghcr.io/org/app:buildcache PUSH=1 IMAGE=reg/app:1 ./build.sh
#
# Config precedence: explicit env  >  .env  >  defaults.
# .env is untrusted input: only the five allowlisted keys are read and
# values are taken literally - never eval'd.
# Default CACHE_REF is project-scoped: 127.0.0.1:5000/<dir>:buildcache,
# so two projects never share one cache ref by accident.
#
# Keys: CACHE_REF, IMAGE, PUSH, DOCKERFILE, CONTEXT
#
# Trust: this wrapper ALWAYS exports cache (mode=max). It is a trusted-local
# tool - run it only on checkouts you trust, with registry credentials you
# control. Never hand shared-ref write credentials to untrusted code; in CI,
# use the import-only PR pattern in ci/github-actions.yml.
set -euo pipefail

CACHE_REF="${CACHE_REF:-}"
IMAGE="${IMAGE:-}"
PUSH="${PUSH:-0}"
DOCKERFILE="${DOCKERFILE:-Dockerfile}"
CONTEXT="${CONTEXT:-.}"

if [[ -f .env ]]; then
  while IFS='=' read -r key value; do
    [[ -n "$key" ]] || continue
    value="${value%$'\r'}"
    case "$key" in
      CACHE_REF)  : "${CACHE_REF:=$value}" ;;
      IMAGE)      : "${IMAGE:=$value}" ;;
      PUSH)       : "${PUSH:=$value}" ;;
      DOCKERFILE) : "${DOCKERFILE:=$value}" ;;
      CONTEXT)    : "${CONTEXT:=$value}" ;;
    esac
  done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env || true)
fi

CACHE_REF="${CACHE_REF:-127.0.0.1:5000/$(basename "$PWD"):buildcache}"

# `--` passthrough: everything after it goes to buildx verbatim.
EXTRA_ARGS=()
if [[ "${1:-}" == "--" ]]; then
  shift
  EXTRA_ARGS=("$@")
fi

[[ -f "$DOCKERFILE" ]] || { echo "Dockerfile not found: $DOCKERFILE" >&2; exit 1; }
[[ "$PUSH" == "1" && -z "$IMAGE" ]] && { echo "PUSH=1 requires IMAGE=<registry/image:tag>" >&2; exit 1; }

args=(build --file "$DOCKERFILE"
  "--cache-from=type=registry,ref=${CACHE_REF}"
  "--cache-to=type=registry,ref=${CACHE_REF},mode=max")

if [[ "$PUSH" == "1" ]]; then
  args+=("--push")
  [[ -n "$IMAGE" ]] && args+=("-t" "$IMAGE")
else
  args+=("--load")
  [[ -n "$IMAGE" ]] && args+=("-t" "$IMAGE")
fi

if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
  args+=("${EXTRA_ARGS[@]}")
fi
args+=("$CONTEXT")

echo "+ docker buildx ${args[*]}"
exec docker buildx "${args[@]}"
