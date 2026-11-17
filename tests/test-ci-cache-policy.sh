#!/usr/bin/env bash
# Static contract checks for the kit's cache access policy.
#
# Policy: the shared cache ref has ONE trusted writer (the default branch in
# CI, or the developer's own local registry). Untrusted builds (PRs / MRs)
# IMPORT only - a broken or malicious PR can never refresh the shared cache.
# The registry templates already enforce this; these checks pin it so a
# well-meaning edit cannot silently drop the guard. The gha variant must
# document GitHub's cache write restrictions (read-only triggers).

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

CI_DIR="$HERE/../ci"
GHA_REG="$CI_DIR/github-actions.yml"
GHA_NATIVE="$CI_DIR/github-actions-gha.yml"
GITLAB="$CI_DIR/gitlab-ci.yml"

# gha_step_block <file> <marker> — a GitHub Actions step: from the marker line
# to the next sibling step (steps are indented 6 spaces in these templates).
gha_step_block() {
  awk -v m="$2" 'index($0, m) { f=1; next } f && /^      - name:/ { exit } f { print }' "$1"
}

# gitlab_job_block <file> <job> — from a top-level job key to the next one.
gitlab_job_block() {
  awk -v j="$2:" '$0 == j { f=1; next } f && /^[a-z]/ { exit } f { print }' "$1"
}

pr_block="$(gha_step_block "$GHA_REG" "Build (PR")"
main_block="$(gha_step_block "$GHA_REG" "Build (main")"
mr_block="$(gitlab_job_block "$GITLAB" "build:merge-request")"
default_block="$(gitlab_job_block "$GITLAB" "build:default-branch")"

# --- registry backend (GitHub Actions): single-writer policy -------------------

t "PR build imports the cache" assert_contains "$pr_block" "cache-from"
no_pr_export() { [[ "$pr_block" != *cache-to* ]]; }
t "PR build never exports the cache" no_pr_export
t "main build imports the cache" assert_contains "$main_block" "cache-from"
t "main build refreshes the shared cache (mode=max)" \
  assert_contains "$main_block" "cache-to"
t "main export uses mode=max" assert_contains "$main_block" "mode=max"
t "registry login is skipped on pull requests" \
  assert_contains "$(cat "$GHA_REG")" "if: github.event_name != 'pull_request'"

# --- registry backend (GitLab): same policy -------------------------------------

t "MR build imports the cache" assert_contains "$mr_block" "cache-from"
no_mr_export() { [[ "$mr_block" != *cache-to* ]]; }
t "MR build never exports the cache" no_mr_export
t "default-branch build refreshes the shared cache" \
  assert_contains "$default_block" "cache-to"

# --- gha backend: platform isolation + documented write restrictions ------------

t "gha template keeps cache export (platform isolates PR writes)" \
  assert_contains "$(cat "$GHA_NATIVE")" "cache-to: type=gha"
t "gha template documents read-only cache triggers" \
  assert_contains "$(cat "$GHA_NATIVE")" "pull_request_target"
t "gha template names the multi-image scope pitfall" \
  assert_contains "$(cat "$GHA_NATIVE")" "default scope"

# --- wrappers: trusted-local tools, always export -------------------------------

t "build.sh declares its trust boundary" \
  assert_contains "$(cat "$HERE/../templates/build.sh")" "trusted-local"
t "build.ps1 declares its trust boundary" \
  assert_contains "$(cat "$HERE/../templates/build.ps1")" "trusted-local"

suite_done "ci-cache-policy"