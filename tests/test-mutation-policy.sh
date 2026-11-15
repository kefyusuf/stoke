#!/usr/bin/env bash
# S2/S3 unit contract — setup/lib/common.sh mutation policy
#
# kit_run: the single choke point for system mutations.
#   normal mode      -> executes
#   KIT_DRY_RUN=1    -> prints "[DRY-RUN] <cmd>", executes nothing
#
# kit_consent: the gate before the first mutation.
#   dry-run                 -> never prompts
#   KIT_YES=1               -> proceeds without reading stdin
#   stdin 'y'/'yes'         -> proceeds
#   stdin 'n' or EOF        -> exit 1, message names KIT_YES, nothing done
#
# Nothing real is ever executed: the kit_run execution test targets a
# purpose-built stub, never sudo/apt.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../setup/lib/common.sh"

# --- kit_run ---------------------------------------------------------------------

# Normal mode executes: sandboxed PATH, harmless custom stub as the target.
sandbox_new
sandbox_path
stub_cmd kit-fake-mutation ''
kit_run kit-fake-mutation --do-work >/dev/null
t "kit_run executes in normal mode (stub got called)" \
  assert_contains "$(sandbox_calls)" "kit-fake-mutation --do-work"

# Dry-run: print the exact command, execute nothing (3>&1 captures the
# fd-3 notice channel into the same string).
sandbox_reset
out="$(KIT_DRY_RUN=1 kit_run sudo apt-get install -y docker-ce 3>&1 2>&1)"
t "kit_run: dry-run prints the exact command" \
  assert_contains "$out" "[DRY-RUN] sudo apt-get install -y docker-ce"
t "kit_run: dry-run executes nothing" \
  assert_eq "0" "$(grep -c 'kit-fake-mutation' <<<"$(sandbox_calls)" || true)"

# --- kit_consent ---------------------------------------------------------------------

consent_y() { printf 'y\n' | kit_consent "Summary."; }
consent_yes() { printf 'yes\n' | kit_consent "Summary."; }
# kit_consent aborts via `exit 1` (the script's last gate) - call it inside a
# subshell so the abort doesn't terminate this suite.
consent_n_aborts() { ( printf 'n\n' | kit_consent "Summary." ) >/dev/null 2>&1; [[ $? -eq 1 ]]; }
consent_eof_aborts() { ( kit_consent "Summary." </dev/null ) >/dev/null 2>&1; [[ $? -eq 1 ]]; }
consent_unattended() { KIT_YES=1 kit_consent "Summary." </dev/null; }
consent_dryrun_noprompt() {
  local o; o="$(KIT_DRY_RUN=1 kit_consent "Summary." 2>&1)"
  ! grep -q 'Proceed?' <<<"$o" && grep -q 'DRY-RUN' <<<"$o"
}

t "consent: stdin 'y' proceeds" consent_y
t "consent: stdin 'yes' proceeds" consent_yes
t "consent: stdin 'n' aborts with rc 1" consent_n_aborts
t "consent: EOF aborts with rc 1" consent_eof_aborts
msg="$(kit_consent "Summary." </dev/null 2>&1)"
t "consent: EOF message names the unattended override" assert_contains "$msg" "KIT_YES"
t "consent: KIT_YES=1 proceeds without stdin" consent_unattended
t "consent: dry-run never prompts, explains itself" consent_dryrun_noprompt

suite_done "mutation-policy"
