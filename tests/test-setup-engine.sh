#!/usr/bin/env bash
# S2/S3 CLI contract — setup/setup-engine.sh
#
# The flagship mutating script must honor the kit-wide mutation policy:
#   --dry-run / KIT_DRY_RUN=1   -> print every mutation, execute nothing, rc 0
#   default (non-TTY stdin)     -> consent gate aborts with 1, nothing executed
#   --yes / KIT_YES=1           -> full run under stubs, all mutations attempted
#   --help                      -> documents the contract, rc 0
#   unknown flag                -> rc 2
#
# All externals are stubbed; nothing outside the sandbox is touched.
# /etc/os-release is redirected via KIT_OS_RELEASE_FILE (a deliberate
# dependency-injection seam, also useful on exotic distros).

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

ENGINE="$HERE/../setup/setup-engine.sh"
WSL2_REL='5.15.167.4-microsoft-standard-WSL2'
OSREL=""

# engine_run <envspec> [args...] — sets ENGINE_OUT (stdout+stderr) and
# ENGINE_RC. Always stdin-closed so the consent gate takes the deterministic
# EOF path in non-interactive runs.
engine_run() {
  local envspec="${1:-}"; shift || true
  sandbox_new
  sandbox_path
  stub_cmd uname "$WSL2_REL"
  # sudo must pass through to the other stubs (the script mutates via sudo).
  cat > "$SB_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "sudo $*" >> "$STUB_LOG"
exec "$@"
EOF
  chmod +x "$SB_BIN/sudo"
  stub_cmd apt-get ''
  stub_cmd curl ''
  stub_cmd install ''
  stub_cmd chmod ''
  stub_cmd tee ''
  stub_cmd dpkg 'amd64'
  stub_cmd systemctl 'running'
  stub_cmd groupadd ''
  stub_cmd usermod ''
  OSREL="$(mktemp)"
  printf 'ID=ubuntu\nVERSION_CODENAME=jammy\n' > "$OSREL"
  ENGINE_OUT="$( ( export KIT_OS_RELEASE_FILE="$OSREL"
                   if [[ -n "${envspec:-}" ]]; then export "${envspec%%=*}"="${envspec#*=}"; fi
                   bash "$ENGINE" "$@" </dev/null ) 2>&1 )"
  ENGINE_RC=$?
}

# --- flag surface ------------------------------------------------------------------

engine_run "" --bogus
t "unknown flag exits 2" assert_eq "2" "$ENGINE_RC"

engine_run "" --help
t "--help exits 0" assert_eq "0" "$ENGINE_RC"
t "--help documents dry-run" assert_contains "$ENGINE_OUT" "--dry-run"
t "--help documents unattended mode" assert_contains "$ENGINE_OUT" "KIT_YES"

# --- S2: dry-run contract ------------------------------------------------------------

engine_run "KIT_DRY_RUN=1"
t "dry-run exits 0" assert_eq "0" "$ENGINE_RC"
t "dry-run prints the apt install it would run" \
  assert_contains "$ENGINE_OUT" "[DRY-RUN] sudo apt-get install -y docker-ce"
t "dry-run prints the config file write it would do" \
  assert_contains "$ENGINE_OUT" "[DRY-RUN] sudo tee"
t "dry-run prints the group change it would do" \
  assert_contains "$ENGINE_OUT" "[DRY-RUN] sudo usermod"
t "dry-run announces completion with no changes" \
  assert_contains "$ENGINE_OUT" "DRY-RUN complete"
t "dry-run never prompts" \
  assert_contains "$(grep -c 'Proceed?' <<<"$ENGINE_OUT" || true)" "0"
t "dry-run executes zero mutations (stub log clean)" \
  assert_eq "0" "$(grep -cE 'apt-get (install|update|remove)|usermod|groupadd|sudo (curl|tee|chmod|install|systemctl enable)' <<<"$(sandbox_calls)" || true)"

# --- S3: consent gate -----------------------------------------------------------------

engine_run ""
t "non-interactive without consent aborts" assert_eq "1" "$ENGINE_RC"
t "abort message says nothing was changed" assert_contains "$ENGINE_OUT" "no changes were made"
t "abort message names the override" assert_contains "$ENGINE_OUT" "KIT_YES"
t "aborted run executed zero mutations" \
  assert_eq "0" "$(grep -cE 'apt-get (install|update|remove)|usermod|groupadd|sudo (curl|tee|chmod|install|systemctl enable)' <<<"$(sandbox_calls)" || true)"

# --- S2b: real (consented) run attempts every mutation -----------------------------------

engine_run "KIT_YES=1"
t "consented run exits 0" assert_eq "0" "$ENGINE_RC"
t "consented run calls apt-get install docker-ce" \
  assert_contains "$(sandbox_calls)" "apt-get install -y docker-ce"
t "consented run removes legacy packages" \
  assert_contains "$(sandbox_calls)" "apt-get remove -y docker.io"
t "consented run enables the docker service" \
  assert_contains "$(sandbox_calls)" "systemctl enable --now docker"
t "consented run adds the user to the docker group" \
  assert_contains "$(sandbox_calls)" "usermod -aG docker"
t "consented run reaches the end (Setup complete)" \
  assert_contains "$ENGINE_OUT" "Setup complete"

# --- stdin consent end-to-end (echo y | script) ---------------------------------------------

engine_out_y="$( ( sandbox_new; sandbox_path
                   stub_cmd uname "$WSL2_REL"
                   cat > "$SB_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "sudo $*" >> "$STUB_LOG"
exec "$@"
EOF
                   chmod +x "$SB_BIN/sudo"
                   stub_cmd apt-get ''; stub_cmd curl ''; stub_cmd install ''
                   stub_cmd chmod ''; stub_cmd tee ''; stub_cmd dpkg 'amd64'
                   stub_cmd systemctl 'running'; stub_cmd groupadd ''; stub_cmd usermod ''
                   OSREL="$(mktemp)"; printf 'ID=ubuntu\nVERSION_CODENAME=jammy\n' > "$OSREL"
                   export KIT_OS_RELEASE_FILE="$OSREL"
                   printf 'y\n' | bash "$ENGINE" ) 2>&1 )"
t "piped 'y' consents and completes" assert_contains "$engine_out_y" "Setup complete"

suite_done "setup-engine"
