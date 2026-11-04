#!/usr/bin/env bash
# Cache-aware buildx wrapper (Linux / WSL2). Windows twin: build.ps1.
#
# Usage (from your project root, Dockerfile in place):
#   CACHE_REF=127.0.0.1:5000/myapp:buildcache ./build.sh            # local registry
#   CACHE_REF=ghcr.io/org/myapp:buildcache PUSH=1 ./build.sh        # CI-shared
#
# Env:
#   CACHE_REF   registry ref for the BuildKit cache   (default: local registry)
#   IMAGE       tag for the built image               (optional; PUSH=1 needs it or CI tags it)
#   PUSH=1      push the image instead of --load      (default 0)
#   DOCKERFILE  path to Dockerfile                    (default Dockerfile)
#   CONTEXT     build context dir                     (default .)
set -euo pipefail

CACHE_REF="${CACHE_REF:-127.0.0.1:5000/myapp:buildcache}"
IMAGE="${IMAGE:-}"
PUSH="${PUSH:-0}"
DOCKERFILE="${DOCKERFILE:-Dockerfile}"
CONTEXT="${CONTEXT:-.}"

[[ -f "$DOCKERFILE" ]] || { echo "Dockerfile not found: $DOCKERFILE" >&2; exit 1; }
[[ "$PUSH" == "1" && -z "$IMAGE" ]] && { echo "PUSH=1 requires IMAGE=<registry/image:tag>" >&2; exit 1; }

args=(build --file "$DOCKERFILE")

# Import: any machine (CI or teammate) that pushed this ref warms this build.
args+=("--cache-from=type=registry,ref=${CACHE_REF}")

# Export: mode=max stores ALL stages (multi-stage reuse), not just the final image.
args+=("--cache-to=type=registry,ref=${CACHE_REF},mode=max")

if [[ "$PUSH" == "1" ]]; then
  args+=("--push")
  [[ -n "$IMAGE" ]] && args+=("-t" "$IMAGE")
else
  args+=("--load")
  [[ -n "$IMAGE" ]] && args+=("-t" "$IMAGE")
fi

args+=("$CONTEXT")

echo "+ docker buildx ${args[*]}"
exec docker buildx "${args[@]}"
