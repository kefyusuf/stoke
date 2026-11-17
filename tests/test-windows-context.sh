#!/usr/bin/env bash
# Static contract checks for setup/windows-context.ps1. The real bridge path
# (drop-in + listener + Windows context + -Undo) is exercised on a Windows
# runner by .github/workflows/windows-e2e.yml; these pin the exact regression
# that shipped once: `-H fd` (bare) parses as a TCP host in docker/cli's
# opts.ParseHost - socket activation requires `-H fd://`.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

PS1="$HERE/../setup/windows-context.ps1"
execstart="$(grep 'ExecStart=/usr/bin/dockerd' "$PS1" || true)"

t "drop-in uses fd:// socket activation" assert_contains "$execstart" "-H fd://"
# shellcheck disable=SC2016  # single quotes intentional: $1 expands in the inner shell
t "drop-in never uses bare -H fd (parses as tcp://fd:2375)" \
  bash -c '! grep -q -- "-H fd -H" "$1"' _ "$PS1"
t "TCP listener stays loopback-only" assert_contains "$execstart" "-H tcp://127.0.0.1:"
# shellcheck disable=SC2016  # literal PowerShell param declaration, no expansion wanted
t "-Undo switch exists" assert_contains "$(cat "$PS1")" '[switch]$Undo'

suite_done "windows-context"