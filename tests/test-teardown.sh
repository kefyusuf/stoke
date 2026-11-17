#!/usr/bin/env bash
# S4 - teardown contract (setup/teardown.sh)
#
# teardown.sh reverses, in safe order, every mutation the kit's setup
# scripts perform (the mirror of the SECURITY.md touch table):
#   containers down -> context rm -> services off -> group out ->
#   packages purge -> apt repo files rm -> optional .wslconfig restore
#
# Optional-only: --purge-data and --restore-wslconfig must be ABSENT by
# default - a plain teardown never deletes data or config.
#
# Everything external is stubbed; HOME / .wslconfig path / docker data
# root are redirected via KIT_WSLCONFIG and KIT_DOCKER_DATA_ROOT.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

TEARDOWN="$HERE/../setup/teardown.sh"
WSL2_REL='5.15.167.4-microsoft-standard-WSL2'

# Stable seam paths (KIT_WSLCONFIG / KIT_DOCKER_DATA_ROOT) — independent of
# per-run sandboxes so tests can pre-seed backups / data dirs.
SUITE_HOME="$("$REAL_MKTEMP" -d)"
export KIT_WSLCONFIG="$SUITE_HOME/.wslconfig"
export KIT_DOCKER_DATA_ROOT="$SUITE_HOME/docker-data"
# no ownership record here: exercises the warned full-reversal fallback
export KIT_STATE_DIR="$SUITE_HOME/state"

td_run() {
  local envspec="$1"; shift || true
  sandbox_new
  sandbox_path
  stub_cmd uname "$WSL2_REL"
  cat > "$SB_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "sudo $*" >> "$STUB_LOG"
exec "$@"
EOF
  "$REAL_CHMOD" +x "$SB_BIN/sudo"
  for c in systemctl apt-get docker gpasswd groupdel rm cp rmdir; do stub_cmd "$c" ''; done
  # optional per-run stubs: TD_EXTRA_STUBS=("name=canned stdout" ...)
  local spec
  for spec in ${TD_EXTRA_STUBS[@]+"${TD_EXTRA_STUBS[@]}"}; do
    stub_cmd "${spec%%=*}" "${spec#*=}"
  done
  TD_EXTRA_STUBS=()
  TD_OUT="$( ( export HOME="$SUITE_HOME"
              if [[ -n "${envspec:-}" ]]; then export "${envspec%%=*}"="${envspec#*=}"; fi
              bash "$TEARDOWN" "$@" </dev/null ) 2>&1 3>&1 )"
  TD_RC=$?
}

# mutation lines in the stub log (excludes probes like "docker info", "uname -r")
logged_mutations() { grep -E 'sudo |docker (compose|context)|gpasswd|groupdel|cp ' <<<"$(sandbox_calls)" || true; }

# --- flag surface ---------------------------------------------------------------

td_run "" --bogus
t "unknown flag exits 2" assert_eq "2" "$TD_RC"

td_run "" --help
t "--help exits 0" assert_eq "0" "$TD_RC"
t "--help documents --purge-data" assert_contains "$TD_OUT" "--purge-data"
t "--help documents --restore-wslconfig" assert_contains "$TD_OUT" "--restore-wslconfig"

# --- S2 inheritance: dry-run + consent -------------------------------------------

td_run "KIT_DRY_RUN=1"
t "dry-run exits 0" assert_eq "0" "$TD_RC"
t "dry-run prints the package purge it would run" \
  assert_contains "$TD_OUT" "[DRY-RUN] sudo apt-get purge -y docker-ce"
t "dry-run announces completion" assert_contains "$TD_OUT" "DRY-RUN complete"
t "dry-run executes zero mutations" assert_eq "" "$(logged_mutations)"

td_run ""
t "non-interactive without consent aborts" assert_eq "1" "$TD_RC"
t "abort message says nothing was changed" assert_contains "$TD_OUT" "no changes were made"
t "aborted run executed zero mutations" assert_eq "" "$(logged_mutations)"

# --- consented teardown: the full reversal, in order ------------------------------

td_run "KIT_YES=1"
t "consented teardown exits 0" assert_eq "0" "$TD_RC"
t "stops containers first (compose down)" \
  assert_contains "$(sandbox_calls)" "docker compose -f cache-stack/docker-compose.registry.yml down"
t "removes the kit docker context" \
  assert_contains "$(sandbox_calls)" "docker context rm -f kit-engine"
t "disables docker + docker.socket" \
  assert_contains "$(sandbox_calls)" "systemctl disable --now docker docker.socket"
t "removes the user from the docker group" \
  assert_contains "$(sandbox_calls)" "gpasswd -d"
t "deletes the docker group" assert_contains "$(sandbox_calls)" "groupdel docker"
t "purges the docker packages" \
  assert_contains "$(sandbox_calls)" "apt-get purge -y docker-ce"
t "removes apt repo + keyring files" \
  assert_contains "$(sandbox_calls)" "rm -f /etc/apt/sources.list.d/docker.list"
t "keeps docker data by default" \
  assert_eq "0" "$(grep -c 'rm -rf' <<<"$(sandbox_calls)")"
t "does not touch .wslconfig without the flag" \
  assert_eq "0" "$(grep -c ' cp ' <<<"$(sandbox_calls)")"

# order: containers die before packages are purged
reversal_order_ok() {
  local n_compose n_purge
  n_compose="$(grep -n 'compose -f' <<<"$(sandbox_calls)" | head -1 | cut -d: -f1)"
  n_purge="$(grep -n 'apt-get purge' <<<"$(sandbox_calls)" | head -1 | cut -d: -f1)"
  [[ -n "$n_compose" && -n "$n_purge" && "$n_compose" -lt "$n_purge" ]]
}
t "order: compose down runs before apt purge" reversal_order_ok

# --- optional flags ----------------------------------------------------------------

mkdir -p "$KIT_DOCKER_DATA_ROOT"; echo x > "$KIT_DOCKER_DATA_ROOT/blob"
td_run "KIT_YES=1" --purge-data
t "--purge-data removes the docker data root" \
  assert_contains "$(sandbox_calls)" "rm -rf $KIT_DOCKER_DATA_ROOT"
t "--purge-data run still exits 0" assert_eq "0" "$TD_RC"

td_run "KIT_YES=1" --restore-wslconfig
t "restore without any backup warns but succeeds" assert_eq "0" "$TD_RC"
t "restore warns that no backup was found" assert_contains "$TD_OUT" "no backup"

# newest backup wins (backup filenames sort chronologically)
printf 'old limits' > "$SUITE_HOME/.wslconfig.bak.20260101-000000"
printf 'new limits' > "$SUITE_HOME/.wslconfig.bak.20260202-111111"
td_run "KIT_YES=1" --restore-wslconfig
t "restore copies the NEWEST backup over .wslconfig" \
  assert_contains "$(sandbox_calls)" "cp $KIT_WSLCONFIG.bak.20260202-111111"

# --- default restore path: the WINDOWS profile, not WSL $HOME -------------------
# setup-wsl.ps1 backs up %USERPROFILE%\.wslconfig; without KIT_WSLCONFIG the
# teardown must resolve that profile through WSL interop (cmd.exe + wslpath).

mkdir -p "$SUITE_HOME/winprofile"
printf 'windows limits' > "$SUITE_HOME/winprofile/.wslconfig.bak.20260303-222222"
TD_EXTRA_STUBS=('cmd.exe=C:\Users\kitrunner' "wslpath=$SUITE_HOME/winprofile")
td_run "KIT_WSLCONFIG=" --yes --restore-wslconfig
t "default restore resolves the Windows profile via interop" \
  assert_contains "$(sandbox_calls)" "cp $SUITE_HOME/winprofile/.wslconfig.bak.20260303-222222"

# --- windows-context bridge cleanup (only when the bridge was applied) ----------

export KIT_TCP_DROPIN="$SUITE_HOME/kit-tcp.conf"
td_run "KIT_YES=1"
t "no bridge drop-in: no bridge cleanup attempted" \
  assert_eq "0" "$(grep -c 'kit-tcp' <<<"$(sandbox_calls)" || true)"

printf '[Service]\n' > "$KIT_TCP_DROPIN"
td_run "KIT_YES=1"
t "removes the kit-tcp.conf drop-in" \
  assert_contains "$(sandbox_calls)" "rm -f $KIT_TCP_DROPIN"
t "reloads systemd after drop-in removal" \
  assert_contains "$(sandbox_calls)" "systemctl daemon-reload"
t "without Windows interop, points at -Undo for the kit-wsl context" \
  assert_contains "$TD_OUT" "kit-wsl"

TD_EXTRA_STUBS=('docker.exe=')
td_run "KIT_YES=1"
t "removes the Windows-side kit-wsl context via interop" \
  assert_contains "$(sandbox_calls)" "docker.exe context rm -f kit-wsl"

printf '[Service]\n' > "$KIT_TCP_DROPIN"
td_run "KIT_DRY_RUN=1"
t "dry-run previews the drop-in removal" \
  assert_contains "$TD_OUT" "[DRY-RUN] sudo rm -f $KIT_TCP_DROPIN"
t "dry-run bridge cleanup executes nothing" \
  assert_eq "0" "$(grep -c 'kit-tcp' <<<"$(sandbox_calls)" || true)"

suite_done "teardown"
