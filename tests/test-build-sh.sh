#!/usr/bin/env bash
# S7 - build wrapper contract (templates/build.sh)
#
# The cache wrapper is the kit's daily-driver command, so its defaults
# must be project-aware:
#   CACHE_REF default = 127.0.0.1:5000/<dirname>:buildcache (no more shared
#   "myapp" ref across projects); .env can supply config (allowlisted keys,
#   parsed literally - never eval'd); explicit env beats .env; `--` passes
#   extra buildx args through verbatim.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

BUILD="$HERE/../templates/build.sh"
B_ENV=""

# b_run <dir> [args...] — runs build.sh inside <dir> with a logging docker
# stub; sets B_OUT / B_RC. Optional single "VAR=val" via B_ENV global.
b_run() {
  local dir="$1"; shift
  sandbox_new
  sandbox_path
  stub_cmd docker ''
  B_OUT="$( ( cd "$dir"
             for pair in ${B_ENV:-}; do export "${pair%%=*}"="${pair#*=}"; done
             bash "$BUILD" "$@" </dev/null ) 2>&1 )"
  B_RC=$?
}

# new_project <name> — fresh project dir with a minimal Dockerfile.
new_project() {
  local dir; dir="$("$REAL_MKTEMP" -d)/$1"
  mkdir -p "$dir"
  printf 'FROM scratch\n' > "$dir/Dockerfile"
  printf '%s' "$dir"
}

# --- defaults -----------------------------------------------------------------

proj="$(new_project proj-alpha)"
b_run "$proj"
t "default CACHE_REF derives from the project dir name" \
  assert_contains "$(sandbox_calls)" "ref=127.0.0.1:5000/proj-alpha:buildcache"
t "buildx build invoked" assert_contains "$(sandbox_calls)" "buildx"

# --- .env layer ------------------------------------------------------------------

proj="$(new_project proj-beta)"
printf 'CACHE_REF=127.0.0.1:5000/envfile:buildcache\n' > "$proj/.env"
b_run "$proj"
t ".env supplies CACHE_REF when env unset" \
  assert_contains "$(sandbox_calls)" "ref=127.0.0.1:5000/envfile:buildcache"

proj="$(new_project proj-gamma)"
printf 'CACHE_REF=127.0.0.1:5000/envfile2:buildcache\n' > "$proj/.env"
B_ENV="CACHE_REF=127.0.0.1:5000/explicit:buildcache"
b_run "$proj"
t "explicit env beats .env" \
  assert_contains "$(sandbox_calls)" "ref=127.0.0.1:5000/explicit:buildcache"
B_ENV=""

# .env is untrusted input: unknown keys are ignored, values never eval'd
proj="$(new_project proj-delta)"
printf 'EVIL=$(rm -rf /tmp/should-not-run)\nCACHE_REF=127.0.0.1:5000/delta:buildcache\n' > "$proj/.env"
b_run "$proj"
t "unknown .env keys ignored, values not eval'd" \
  assert_eq "0" "$(grep -c 'rm -rf' <<<"$(sandbox_calls)")"
t "allowlisted .env key still applied" \
  assert_contains "$(sandbox_calls)" "ref=127.0.0.1:5000/delta:buildcache"

# --- passthrough and validation ----------------------------------------------------

proj="$(new_project proj-eps)"
b_run "$proj" -- --platform linux/arm64
t "-- passes buildx args through verbatim" \
  assert_contains "$(sandbox_calls)" "--platform linux/arm64"

proj="$(new_project proj-zeta)"
b_run "$proj"
t "PUSH default is --load (no push)" \
  assert_contains "$(sandbox_calls)" "--load"

proj="$(new_project proj-eta)"
B_ENV="PUSH=1"
b_run "$proj"
t "PUSH=1 without IMAGE aborts" assert_eq "1" "$B_RC"
B_ENV=""

proj="$(new_project proj-theta)"
B_ENV="PUSH=1 IMAGE=127.0.0.1:5000/proj-theta:latest"
b_run "$proj"
t "PUSH=1 with IMAGE pushes and tags" \
  assert_contains "$(sandbox_calls)" "--push"
B_ENV=""

suite_done "build-sh"
