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

# Second shipped regression: with $ErrorActionPreference="Stop", 2>$null leaks
# native stderr into captured output - [bool](docker context inspect ... 2>$null)
# said "exists" for an absent context, so the bridge never created it and the
# -Undo assertion false-positived. Existence must be an exit-code check.
E2E="$HERE/../.github/workflows/windows-e2e.yml"

# shellcheck disable=SC2016  # literal PowerShell text, no expansion wanted
t "context existence check suppresses all streams (exit-code based)" \
  grep -Fq 'docker context inspect kit-wsl *>$null' "$PS1"
no_bool_truthiness() { ! grep -Fq '[bool](& docker' "$PS1"; }
t "no output-truthiness context check" no_bool_truthiness
# shellcheck disable=SC2016  # literal PowerShell text, no expansion wanted
t "e2e -Undo assertion is exit-code based" \
  grep -Fq 'if ($LASTEXITCODE -eq 0) { throw "kit-wsl context still present' "$E2E"
t "e2e bridge step fails fast when the context does not serve" \
  grep -Fq 'kit-wsl context does not serve the engine' "$E2E"

suite_done "windows-context"
