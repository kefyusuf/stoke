#!/usr/bin/env bash
# S1 — WSL2 platform guard contract (setup/lib/common.sh)
#
# The seam: every WSL-side script decides "may I run here?" through
# kit_require_wsl2, whose verdict comes from kit_detect_platform. Real WSL1 /
# WSL2 / native-Linux hosts are not needed: tests stub `uname` on PATH to
# simulate the three kernel families.
#
# Contract:
#   - WSL2 kernel release (modern `...-microsoft-standard-WSL2` or older
#     `...-microsoft-standard`)      -> wsl2
#   - WSL1 kernel release (`...-Microsoft`) -> wsl1
#   - anything else (native Linux, broken uname) -> linux (not WSL)
#   - guard: wsl2 passes; WSL1 gets the fix command and exit 1; other
#     non-WSL2 hosts exit 1 unless KIT_ALLOW_LINUX=1.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

# Red phase: this file does not exist yet, so every case below fails until
# setup/lib/common.sh implements the contract.
LIB="$HERE/../setup/lib/common.sh"
source "$LIB"

# --- helpers -------------------------------------------------------------------

# platform_for <kernel-release> — kit_detect_platform verdict for a simulated
# kernel release (uname stubbed in a fresh sandbox).
platform_for() {
  sandbox_new
  sandbox_path
  stub_cmd uname "$1"
  kit_detect_platform
}

# guard_run <kernel-release> [VAR=val ...] — run kit_require_wsl2 in a subshell
# against a simulated kernel; prints the exit code on line 1, then the output.
guard_run() {
  local rel="$1"; shift
  sandbox_new
  sandbox_path
  stub_cmd uname "$rel"
  local var
  for var in "$@"; do export "${var%%=*}"="${var#*=}"; done
  local out rc
  out="$( ( kit_require_wsl2 ) 2>&1 )"
  rc=$?
  for var in "$@"; do unset "${var%%=*}"; done
  printf '%s\n%s' "$rc" "$out"
}

# --- detection correctness -------------------------------------------------------

t "detect: modern WSL2 kernel -> wsl2" \
  assert_eq "wsl2" "$(platform_for '5.15.167.4-microsoft-standard-WSL2')"
t "detect: older WSL2 kernel (no WSL2 suffix) -> wsl2" \
  assert_eq "wsl2" "$(platform_for '4.19.104-microsoft-standard')"
t "detect: WSL1 kernel -> wsl1" \
  assert_eq "wsl1" "$(platform_for '4.4.0-19041-Microsoft')"
t "detect: native Linux kernel -> linux" \
  assert_eq "linux" "$(platform_for '6.8.0-56-generic')"
t "detect: broken/missing uname -> linux (not WSL)" \
  assert_eq "linux" "$(platform_for '')"

# --- guard behavior ---------------------------------------------------------------

G="$(guard_run '5.15.167.4-microsoft-standard-WSL2')"
t "guard: WSL2 passes" assert_eq "0" "${G%%$'\n'*}"

G="$(guard_run '4.4.0-19041-Microsoft')"
t "guard: WSL1 exits 1" assert_eq "1" "${G%%$'\n'*}"
t "guard: WSL1 message shows the conversion command" \
  assert_contains "$G" "wsl --set-version"

t "guard: WSL1 override via KIT_ALLOW_LINUX=1" \
  assert_eq "0" "$(guard_run '4.4.0-19041-Microsoft' KIT_ALLOW_LINUX=1 | head -1)"

G="$(guard_run '6.8.0-56-generic')"
t "guard: native Linux exits 1" assert_eq "1" "${G%%$'\n'*}"
t "guard: native Linux message names the override" \
  assert_contains "$G" "KIT_ALLOW_LINUX"
t "guard: KIT_ALLOW_LINUX=1 permits native Linux" \
  assert_eq "0" "$(guard_run '6.8.0-56-generic' KIT_ALLOW_LINUX=1 | head -1)"

suite_done "env-guard"
