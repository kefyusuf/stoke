#!/usr/bin/env bash
# S8 - init-project contract (setup/init-project.sh)
#
# Scaffolder: init-project.sh <stack> <name> [target] copies the chosen
# stack template + cache wrappers into a fresh project dir and writes a
# .env with project-scoped CACHE_REF/IMAGE. Kit mutation policy applies:
# --dry-run previews, consent gate before creation, --yes unattended.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

INIT="$HERE/../setup/init-project.sh"
WSL2_REL='5.15.167.4-microsoft-standard-WSL2'

i_run() { # i_run <cwd> <args...> — sets I_OUT / I_RC; stdin closed
  local cwd="$1"; shift
  sandbox_new
  sandbox_path
  stub_cmd uname "$WSL2_REL"
  I_OUT="$( ( cd "$cwd" && bash "$INIT" "$@" </dev/null ) 2>&1 )"
  I_RC=$?
}

# assertion helpers (t runs "$@" - [[ ]] is a keyword, not reachable that way)
file_contains() { [[ $(<"$1") == *"$2"* ]]; }
file_absent()  { [[ ! -e "$1" ]]; }
file_present() { [[ -e "$1" ]]; }

# --- arg surface -----------------------------------------------------------------

work="$("$REAL_MKTEMP" -d)"
i_run "$work" rust
t "missing name exits 2 with usage" assert_eq "2" "$I_RC"
t "usage mentions stacks" assert_contains "$I_OUT" "node-ts"

i_run "$work" node myproj
t "unknown stack exits 2" assert_eq "2" "$I_RC"

i_run "$work" rust "../escape"
t "path-traversal name rejected" assert_eq "2" "$I_RC"

# --- dry-run creates nothing --------------------------------------------------------

i_run "$work" rust myproj --dry-run
t "dry-run exits 0" assert_eq "0" "$I_RC"
t "dry-run prints the copy plan" assert_contains "$I_OUT" "[DRY-RUN]"
t "dry-run creates no directory" file_absent "$work/myproj"

# --- consent gate ---------------------------------------------------------------------

i_run "$work" rust myproj
t "non-interactive without consent aborts" assert_eq "1" "$I_RC"
t "abort message says nothing was changed" assert_contains "$I_OUT" "no changes were made"
t "aborted run creates no directory" file_absent "$work/myproj"

# --- consented creation -----------------------------------------------------------------

i_run "$work" rust myproj2 --yes
t "consented init exits 0" assert_eq "0" "$I_RC"
t "project dir created" file_present "$work/myproj2"
t "stack template copied (Cargo.toml)" file_present "$work/myproj2/Cargo.toml"
t "cache wrapper copied (build.sh)" file_present "$work/myproj2/build.sh"
t "windows twin copied (build.ps1)" file_present "$work/myproj2/build.ps1"
t ".env has project-scoped CACHE_REF" file_contains "$work/myproj2/.env" "CACHE_REF=127.0.0.1:5000/myproj2:buildcache"
t ".env IMAGE content" file_contains "$work/myproj2/.env" "IMAGE=127.0.0.1:5000/myproj2:latest"

# --- refuses to clobber -------------------------------------------------------------------

mkdir -p "$work/occupied"
printf 'keep me\n' > "$work/occupied/precious.txt"
i_run "$work" go occupied
t "non-empty target dir refused" assert_eq "1" "$I_RC"
t "existing files untouched" assert_contains "$(cat "$work/occupied/precious.txt")" "keep me"

suite_done "init-project"
