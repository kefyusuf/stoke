#!/usr/bin/env bash
# Smoke test + cache benchmark for wsl2-docker-cache-kit.
#
# What it proves, on your machine:
#   1. Toolchain: docker + buildx present and reachable (no sudo).
#   2. Layer cache speedup: builds the same image twice, reports the time drop.
#   3. Shared-registry cache: pushes cache to a throwaway registry from builder A,
#      then rebuilds from a FRESH builder B via --cache-from -> proves the exact
#      mechanism local<->CI uses. If this passes, CI cache reuse works.
#
# Run inside WSL from the repo root:  ./setup/verify.sh
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"

info()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m  PASS  %s\033[0m\n' "$*"; }
bad()   { printf '\033[1;31m  FAIL  %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m  WARN  %s\033[0m\n' "$*"; }

FAILURES=0
fail() { bad "$*"; FAILURES=$((FAILURES + 1)); }

# --- 0. environment ----------------------------------------------------------
info "Checking environment"

command -v docker >/dev/null || { fail "docker not found. Run setup/setup-engine.sh first."; exit 1; }
docker info >/dev/null 2>&1 || { fail "docker daemon unreachable (permission denied? see docs/faq.md)."; exit 1; }
ok "docker daemon reachable"

docker buildx version >/dev/null 2>&1 || { fail "buildx plugin missing (docker-buildx-plugin)."; exit 1; }
ok "buildx present: $(docker buildx version | awk '{print $2}')"

case "$PWD" in
  /mnt/*) warn "Running from a Windows mount ($PWD). Builds will be slow - move the repo into the distro filesystem." ;;
  *)      ok "Repo lives on the Linux (ext4) filesystem" ;;
esac

# --- 1. local layer-cache speedup ---------------------------------------------
info "Test 1/2: local layer cache (cold vs cached build)"

WORK=$(mktemp -d)
MARKER=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
cat > "$WORK/Dockerfile" <<EOF
# syntax=docker/dockerfile:1
FROM alpine:3.20
COPY marker /marker
RUN echo "build \$MARKER" > /out.txt
FROM alpine:3.20
COPY --from=0 /out.txt /out.txt
EOF
echo "$MARKER" > "$WORK/marker"

t() { date +%s%3N; }
t0=$(t)
docker buildx build --quiet --load -t kit-verify:local "$WORK" >/dev/null
t1=$(t)
docker buildx build --quiet --load -t kit-verify:local "$WORK" >/dev/null
t2=$(t)
cold=$((t1 - t0)); warm=$((t2 - t1))
ok "cold build: ${cold} ms"
ok "warm build: ${warm} ms"
if [ "$warm" -lt "$cold" ]; then
  ok "layer cache speedup: $(( cold / (warm > 0 ? warm : 1) ))x (warm < cold)"
else
  fail "warm build not faster than cold (${warm} vs ${cold} ms) - cache not effective"
fi
docker rmi kit-verify:local >/dev/null 2>&1 || true

# --- 2. shared-registry cache round trip --------------------------------------
info "Test 2/2: registry cache round trip (the local<->CI mechanism)"

PORT="${KIT_VERIFY_PORT:-$(( (RANDOM % 20000) + 30000 ))}"
# Guard: KIT_VERIFY_PORT is operator input flowing into a docker arg — keep it numeric.
case "$PORT" in
  ''|*[!0-9]*) fail "KIT_VERIFY_PORT must be a plain port number, got: '$PORT'"; exit 1 ;;
esac
REG_NAME="kit-verify-registry-$$"
BUILDER_A="kit-verify-a-$$"
BUILDER_B="kit-verify-b-$$"
cleanup() {
  docker buildx rm "$BUILDER_A" >/dev/null 2>&1 || true
  docker buildx rm "$BUILDER_B" >/dev/null 2>&1 || true
  docker rm -f "$REG_NAME" >/dev/null 2>&1 || true
  docker rmi "127.0.0.1:$PORT/kit-verify:cache" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

docker run -d --name "$REG_NAME" -p "127.0.0.1:${PORT}:5000" registry:2 >/dev/null
info "Throwaway registry on 127.0.0.1:${PORT}"

# Wait for the registry to accept connections (no curl dependency - use bash /dev/tcp).
ready=0
for _ in $(seq 1 40); do
  if (exec 3<>"/dev/tcp/127.0.0.1/${PORT}") 2>/dev/null; then ready=1; break; fi
  sleep 0.25
done
[ "$ready" -eq 1 ] || { fail "throwaway registry never became reachable on ${PORT}"; exit 1; }

# Builder A: fresh BuildKit, builds + exports cache to the registry.
# network=host so buildkitd (in its own container) can reach 127.0.0.1:PORT.
docker buildx create --name "$BUILDER_A" --driver docker-container --driver-opt network=host >/dev/null
docker buildx build \
  --builder "$BUILDER_A" \
  --progress=plain \
  --cache-to "type=registry,ref=127.0.0.1:${PORT}/kit-verify:cache,mode=max" \
  "$WORK" > "$WORK/a.log" 2>&1 \
  || { fail "builder A: cache export failed (log kept below)"; tail -20 "$WORK/a.log" || true; exit 1; }
ok "builder A exported cache to the registry (mode=max)"

# Builder B: a brand-new builder with an empty local store -> must pull cache-from.
docker buildx create --name "$BUILDER_B" --driver docker-container --driver-opt network=host >/dev/null
docker buildx build \
  --builder "$BUILDER_B" \
  --progress=plain \
  --cache-from "type=registry,ref=127.0.0.1:${PORT}/kit-verify:cache" \
  "$WORK" > "$WORK/b.log" 2>&1 \
  || { fail "builder B: cache import failed (log kept below)"; tail -20 "$WORK/b.log" || true; exit 1; }

if grep -q "CACHED" "$WORK/b.log"; then
  ok "builder B (fresh, empty store) hit CACHED layers via --cache-from registry"
  ok "=> cross-machine cache reuse (local <-> CI) works on this machine"
else
  fail "builder B found no CACHED layers - registry cache round trip broken (log kept below)"
  tail -30 "$WORK/b.log" || true
fi

# --- summary -------------------------------------------------------------------
echo ""
if [ "$FAILURES" -eq 0 ]; then
  info "ALL CHECKS PASSED - this machine is cache-ready."
else
  info "$FAILURES check(s) failed - see docs/faq.md."
  exit 1
fi
