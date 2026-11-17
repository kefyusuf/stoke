#!/usr/bin/env bash
# S6 - doctor contract (setup/doctor.sh)
#
# doctor is the daily read-only health report: it never mutates, never
# prompts, and exits 1 only on FAIL-grade problems (daemon unreachable,
# CLI shadowed by Desktop). Everything optional (cache registry, mirror)
# is WARN-grade.
#
# The docker CLI is stubbed case-aware; the suite steers its answers via
# two stable files (DOCKER_INFO / DOCKER_PS) between runs.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

DOCTOR="$HERE/../setup/doctor.sh"
WSL2_REL='5.15.167.4-microsoft-standard-WSL2'

# stable steering files for the case-aware docker stub
STUBSTATE="$("$REAL_MKTEMP" -d)"
export DOCTOR_INFO="$STUBSTATE/docker-info.txt"
export DOCKER_PS="$STUBSTATE/docker-ps.txt"
: > "$DOCTOR_INFO"
: > "$DOCKER_PS"

d_run() { # d_run <args...> — sets D_OUT / D_RC; fresh sandbox per run
  sandbox_new
  sandbox_path
  stub_cmd uname "$WSL2_REL"
  stub_cmd systemctl 'running'
  cat > "$SB_BIN/docker" <<EOF
#!/usr/bin/env bash
cmd="\$1"
case "\$cmd" in
  version) if [[ "\${DOCKER_VERSION_RC:-0}" == "0" ]]; then printf '29.9.3\n'; exit 0; else exit 1; fi ;;
  buildx)  printf 'buildx v0.28.0\n'; exit 0 ;;
  context) printf 'kit-engine\n'; exit 0 ;;
  info)    cat "\$DOCTOR_INFO"; exit 0 ;;
  ps)      cat "\$DOCKER_PS"; exit 0 ;;
  system)  printf 'Build Cache Usage: 1.2GB\n'; exit 0 ;;
  *) exit 0 ;;
esac
EOF
  "$REAL_CHMOD" +x "$SB_BIN/docker"
  D_OUT="$( ( export KIT_DOCKER_CLI_PATH="$SB_BIN/docker"
              export DOCKER_VERSION_RC="${DOCKER_VERSION_RC:-0}"
              bash "$DOCTOR" "$@" </dev/null ) 2>&1 )"
  D_RC=$?
}

set_healthy() {
  printf 'kit-cache-registry\nkit-hub-mirror\n' > "$DOCKER_PS"
  printf 'Registry Mirrors:\n 127.0.0.1:5001/\n' > "$DOCTOR_INFO"
}
set_absent() {
  : > "$DOCKER_PS"
  : > "$DOCTOR_INFO"
}

# --- flag surface ------------------------------------------------------------------

d_run --bogus
t "unknown flag exits 2" assert_eq "2" "$D_RC"

d_run -h
t "--help exits 0" assert_eq "0" "$D_RC"
t "--help says read-only" assert_contains "$D_OUT" "Read-only"

# --- healthy environment -------------------------------------------------------------

set_healthy
d_run
t "healthy env exits 0" assert_eq "0" "$D_RC"
t "no FAIL lines in healthy env" assert_eq "0" "$(grep -c '  FAIL' <<<"$D_OUT")"
t "daemon check present" assert_contains "$D_OUT" "daemon"
t "buildx check present" assert_contains "$D_OUT" "buildx"
t "registry container seen" assert_contains "$D_OUT" "kit-cache-registry"
t "mirror container seen" assert_contains "$D_OUT" "kit-hub-mirror"
t "mirror registration seen" assert_contains "$D_OUT" "127.0.0.1:5001"
t "disk usage surfaced" assert_contains "$D_OUT" "1.2GB"
t "summary line present" assert_contains "$D_OUT" "doctor:"

# --- FAIL-grade problems ---------------------------------------------------------------

DOCKER_VERSION_RC=1
d_run
unset DOCKER_VERSION_RC
t "unreachable daemon exits 1" assert_eq "1" "$D_RC"
t "unreachable daemon is FAIL-grade" assert_contains "$D_OUT" "  FAIL"

# CLI shadowed by Desktop's injected binary: the DI seam points at a binary
# whose path contains /mnt/wsl/docker-desktop (no symlink - MSYS ln may copy).
sandbox_new
sandbox_path
stub_cmd uname "$WSL2_REL"
stub_cmd systemctl 'running'
mkdir -p "$SB_BIN/mnt/wsl/docker-desktop"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SB_BIN/mnt/wsl/docker-desktop/docker"
"$REAL_CHMOD" +x "$SB_BIN/mnt/wsl/docker-desktop/docker"
D_OUT="$( ( export KIT_DOCKER_CLI_PATH="$SB_BIN/mnt/wsl/docker-desktop/docker"
            bash "$DOCTOR" </dev/null ) 2>&1 )"
D_RC=$?
t "shadowed CLI exits 1" assert_eq "1" "$D_RC"
t "shadowed CLI names the fix" assert_contains "$D_OUT" "protect-distro.sh fix"

# --- WARN-grade optional components ------------------------------------------------------

set_absent
d_run
t "absent cache stack still exits 0" assert_eq "0" "$D_RC"
t "absent registry is WARN-grade" assert_contains "$D_OUT" "  WARN"
t "absent stack has no FAIL" assert_eq "0" "$(grep -c '  FAIL' <<<"$D_OUT")"

# mirror up but not registered in the daemon
printf 'kit-cache-registry\nkit-hub-mirror\n' > "$DOCKER_PS"
: > "$DOCTOR_INFO"
d_run
t "unregistered mirror warns with the doc hint" \
  assert_contains "$D_OUT" "NOT registered"

suite_done "doctor"
