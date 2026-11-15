#!/usr/bin/env bash
# Shared library for the kit's WSL-side scripts: messaging + the WSL2 platform
# guard. Sourced, not executed.
#
# Seam note (tests/test-env-guard.sh): the guard contract is verified by
# stubbing `uname` on PATH to simulate WSL1/WSL2/native-Linux kernels, so the
# tests need no real hosts:
#   - modern WSL2 kernel: 5.15.167.4-microsoft-standard-WSL2
#   - older WSL2 kernel:  4.19.104-microsoft-standard
#   - WSL1 kernel:        4.4.0-19041-Microsoft
#
# Scripts source this lib BEFORE defining their own helpers, so a script-local
# info/warn/ok/bad still overrides the lib version.

# shellcheck shell=bash

info() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }

# Prints the detected platform: wsl2 | wsl1 | linux.
#
# WSL2 kernel releases contain "microsoft-standard" (modern builds end with
# "-WSL2", older ones like 4.19.x do not); WSL1 releases end "-Microsoft".
# Anything else — native Linux, a broken uname — is not WSL.
kit_detect_platform() {
  local rel
  rel="$(uname -r 2>/dev/null || true)"
  case "$rel" in
    *microsoft-standard*|*WSL2*) printf 'wsl2\n' ;;
    *[Mm]icrosoft*)              printf 'wsl1\n' ;;
    *)                           printf 'linux\n' ;;
  esac
}

# Exit 1 unless running inside WSL2. The one override is KIT_ALLOW_LINUX=1 —
# an explicit operator escape hatch (CI, native-Linux CI hosts); it is never
# set by the kit itself.
kit_require_wsl2() {
  local platform
  platform="$(kit_detect_platform)"
  case "$platform" in
    wsl2) return 0 ;;
    wsl1)
      if [[ "${KIT_ALLOW_LINUX:-0}" == "1" ]]; then
        warn "WSL1 detected, but KIT_ALLOW_LINUX=1 - continuing anyway (not recommended)."
        return 0
      fi
      warn "WSL1 detected. This kit needs WSL2 (systemd, a real Linux kernel)."
      warn "Convert from Windows:  wsl --set-version <distro> 2"
      exit 1
      ;;
    *)
      if [[ "${KIT_ALLOW_LINUX:-0}" == "1" ]]; then
        info "Non-WSL2 host allowed via KIT_ALLOW_LINUX=1."
        return 0
      fi
      warn "This does not look like WSL2 (native Linux or unusual host)."
      warn "The kit targets WSL2; to proceed anyway: KIT_ALLOW_LINUX=1 $0"
      exit 1
      ;;
  esac
}
