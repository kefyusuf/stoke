#!/usr/bin/env bash
# Ownership contract — setup-engine.sh snapshots the pre-install state into
# $KIT_STATE_DIR/ownership.env; teardown.sh reverses ONLY what the kit created.
#
# Scenarios are forced at the PATH level (dpkg-query / getent / id stubs):
#   fresh    - no docker-ce, no docker group, user not in it
#   existing - docker-ce installed, group present, user already a member
#
# The state dir is suite-stable so manifest persistence across re-runs and
# the engine->teardown handoff are tested for real (tee passes through).

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

ENGINE="$HERE/../setup/setup-engine.sh"
TEARDOWN="$HERE/../setup/teardown.sh"
WSL2_REL='5.15.167.4-microsoft-standard-WSL2'
REAL_TEE="$(command -v tee 2>/dev/null || echo tee)"
REAL_RM="$(command -v rm 2>/dev/null || echo rm)"

SUITE_STATE=$("$REAL_MKTEMP" -d)
SUITE_HOME=$("$REAL_MKTEMP" -d)
export KIT_STATE_DIR="$SUITE_STATE"
OWNERSHIP="$SUITE_STATE/ownership.env"

sudo_stub() {
  cat > "$SB_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "sudo $*" >> "$STUB_LOG"
exec "$@"
EOF
  "$REAL_CHMOD" +x "$SB_BIN/sudo"
}

# own_engine_run <fresh|existing> [args...]
own_engine_run() {
  local scenario="$1"; shift || true
  sandbox_new
  sandbox_path
  stub_cmd uname "$WSL2_REL"
  sudo_stub
  stub_cmd apt-get ''
  stub_cmd curl ''
  stub_cmd install ''
  stub_cmd chmod ''
  stub_cmd dpkg 'amd64'
  stub_cmd systemctl 'running'
  stub_cmd groupadd ''
  stub_cmd usermod ''
  # tee passes through so the manifest is REALLY written (into the sandboxed
  # state dir); everything else stays canned.
  cat > "$SB_BIN/tee" <<EOF
#!/usr/bin/env bash
printf '%s\n' "tee \$*" >> "\$STUB_LOG"
exec "$REAL_TEE" "\$@"
EOF
  "$REAL_CHMOD" +x "$SB_BIN/tee"
  if [[ "$scenario" == existing ]]; then
    stub_cmd dpkg-query 'install ok installed' 0
    stub_cmd getent '' 0
    stub_cmd id 'kitrunner docker'
  else
    stub_cmd dpkg-query '' 1
    stub_cmd getent '' 1
    stub_cmd id 'kitrunner'
  fi
  local osrel aptdir
  osrel=$("$REAL_MKTEMP"); printf 'ID=ubuntu\nVERSION_CODENAME=jammy\n' > "$osrel"
  aptdir=$("$REAL_MKTEMP" -d)
  ENGINE_OUT="$( ( export KIT_OS_RELEASE_FILE="$osrel"
                   export KIT_APT_LIST="$aptdir/docker.list"
                   export KIT_APT_KEYRING="$aptdir/docker.asc"
                   bash "$ENGINE" "$@" </dev/null ) 2>&1 3>&1 )"
  ENGINE_RC=$?
}

# own_teardown_run [args...] — consumes whatever manifest is in SUITE_STATE
own_teardown_run() {
  sandbox_new
  sandbox_path
  stub_cmd uname "$WSL2_REL"
  sudo_stub
  local c
  for c in systemctl apt-get docker gpasswd groupdel cp rmdir; do stub_cmd "$c" ''; done
  # rm passes through so the ownership record is REALLY removed; every rm
  # target is sandboxed via the KIT_* seams below.
  cat > "$SB_BIN/rm" <<EOF
#!/usr/bin/env bash
printf '%s\n' "rm \$*" >> "\$STUB_LOG"
exec "$REAL_RM" "\$@"
EOF
  "$REAL_CHMOD" +x "$SB_BIN/rm"
  TD_OUT="$( ( export HOME="$SUITE_HOME"
              export KIT_WSLCONFIG="$SUITE_HOME/.wslconfig"
              export KIT_DOCKER_DATA_ROOT="$SUITE_HOME/docker-data"
              export KIT_TCP_DROPIN="$SUITE_HOME/kit-tcp.conf"
              export KIT_APT_LIST="$SUITE_HOME/docker.list"
              export KIT_APT_KEYRING="$SUITE_HOME/docker.asc"
              bash "$TEARDOWN" "$@" </dev/null ) 2>&1 3>&1 )"
  TD_RC=$?
}

manifest_has() { [[ -f "$OWNERSHIP" ]] && grep -q "^$1$" "$OWNERSHIP"; }

# --- dry-run writes no ownership record -----------------------------------------

own_engine_run fresh --dry-run
t "engine dry-run exits 0" assert_eq "0" "$ENGINE_RC"
t "engine dry-run writes no manifest" bash -c '[[ ! -f "$1" ]]' _ "$OWNERSHIP"

# --- fresh host: snapshot records absence, install proceeds ----------------------

own_engine_run fresh --yes
t "fresh install exits 0" assert_eq "0" "$ENGINE_RC"
t "fresh install installs docker-ce" \
  assert_contains "$(sandbox_calls)" "apt-get install -y docker-ce"
t "manifest records docker-ce absent before install" manifest_has "DOCKER_CE_PRESENT=0"
t "manifest records docker group absent" manifest_has "GROUP_PRESENT=0"
t "manifest records user not in docker group" manifest_has "USER_IN_GROUP=0"

# --- teardown consumes the fresh manifest: full reversal, then record cleanup ----

own_teardown_run --yes
t "teardown with fresh manifest exits 0" assert_eq "0" "$TD_RC"
t "kit-created group is deleted" assert_contains "$(sandbox_calls)" "groupdel docker"
t "kit-added membership is removed" assert_contains "$(sandbox_calls)" "gpasswd -d"
t "kit-installed packages are purged" \
  assert_contains "$(sandbox_calls)" "apt-get purge -y docker-ce"
t "teardown removes the ownership record" bash -c '[[ ! -f "$1" ]]' _ "$OWNERSHIP"

# --- existing host: reuse, no package mutations, ownership preserved -------------

own_engine_run existing --yes
t "existing-engine run exits 0" assert_eq "0" "$ENGINE_RC"
t "existing engine is reused (no docker-ce install)" \
  bash -c '! grep -q "apt-get install -y docker-ce" "$1"' _ "$STUB_LOG"
t "existing-engine run announces reuse" assert_contains "$ENGINE_OUT" "reusing it"
t "manifest records docker-ce pre-existing" manifest_has "DOCKER_CE_PRESENT=1"
t "manifest records group pre-existing" manifest_has "GROUP_PRESENT=1"
t "manifest records user already in group" manifest_has "USER_IN_GROUP=1"

own_teardown_run --yes
t "teardown keeps the pre-existing group" \
  bash -c '! grep -q "groupdel" "$1"' _ "$STUB_LOG"
t "teardown keeps the pre-existing membership" \
  bash -c '! grep -q "gpasswd" "$1"' _ "$STUB_LOG"
t "teardown keeps the pre-existing packages" \
  bash -c '! grep -q "apt-get purge" "$1"' _ "$STUB_LOG"

# --- re-run never overwrites the original snapshot --------------------------------

own_engine_run fresh --yes
t "re-run keeps the original manifest" manifest_has "DOCKER_CE_PRESENT=1"
t "re-run says it keeps the record" assert_contains "$ENGINE_OUT" "keeping"

# --- no manifest (pre-ownership install): warned fallback, full reversal ----------

"$REAL_RM" -f "$OWNERSHIP"
own_teardown_run --yes
t "manifest-less teardown warns" assert_contains "$TD_OUT" "ownership"
t "manifest-less teardown still reverses fully" \
  assert_contains "$(sandbox_calls)" "groupdel docker"

# --- removed legacy packages are reported with a restore path ---------------------

cat > "$OWNERSHIP" <<'EOF'
KIT_OWNERSHIP_VERSION=1
DOCKER_CE_PRESENT=0
GROUP_PRESENT=0
USER_IN_GROUP=0
APT_REPO_PRESENT=0
LEGACY_PRESENT=docker.io containerd
WSLCONF_SYSTEMD=0
EOF
own_teardown_run --yes
t "teardown reports removed legacy packages" assert_contains "$TD_OUT" "docker.io"
t "teardown shows the restore command" assert_contains "$TD_OUT" "apt-get install docker.io"

suite_done "ownership"