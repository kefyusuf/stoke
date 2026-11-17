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
# an explicit operator escape hatch (CI, native-Linux hosts); never set by the
# kit itself.
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

# --- mutation policy -----------------------------------------------------------
# Every system-mutating command in the kit's scripts goes through kit_run;
# every script that mutates asks for consent via kit_consent first. This is
# what makes KIT_DRY_RUN=1 (preview) and KIT_YES=1 (unattended) universal.

# Dry-run notices go to fd 3 (a copy of stderr, opened at lib load) so that
# callers redirecting a kit_run call's stdout AND/OR stderr (`> /dev/null`,
# `2>/dev/null || true`) can never swallow a notice.
exec 3>&2

kit_is_dry_run() { [[ "${KIT_DRY_RUN:-0}" == "1" ]]; }

# kit_run <command...> — execute; or, in dry-run mode, print the exact
# command with a [DRY-RUN] prefix and change nothing.
#
# Pipe caveat: in dry-run the kit_run side of a pipeline does not read stdin,
# so a producer (`foo | kit_run bar`) would get SIGPIPE. For stdin-fed
# mutations use a herestring:  kit_run sudo tee FILE > /dev/null <<< "$data"
kit_run() {
  if kit_is_dry_run; then
    printf '[DRY-RUN] %s\n' "$*" >&3
    return 0
  fi
  "$@"
}

kit_dry_run_footer() {
  info "DRY-RUN complete - nothing was changed. Re-run without KIT_DRY_RUN to apply."
}

# kit_consent <summary...> — print the change summary, then require consent:
#   dry-run           -> no prompt (nothing will change)
#   KIT_YES=1 / --yes -> proceed unattended
#   stdin y/yes       -> proceed
#   stdin n / EOF     -> exit 1 with the unattended hint; nothing was touched
kit_consent() {
  if kit_is_dry_run; then
    info "DRY-RUN: showing what would happen - no confirmation needed."
    printf '%s\n' "$*"
    return 0
  fi
  if [[ "${KIT_YES:-0}" == "1" ]]; then
    info "Unattended mode (KIT_YES=1): skipping confirmation."
    return 0
  fi
  printf '%s\n' "$*"
  local answer=""
  printf 'Proceed? [y/N] '
  if read -r answer; then
    case "$answer" in
      y|Y|yes|Yes|YES) return 0 ;;
    esac
  fi
  warn "Aborted - no changes were made. For unattended runs: KIT_YES=1 (or --yes); to preview: KIT_DRY_RUN=1."
  exit 1
}
