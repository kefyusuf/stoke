#!/usr/bin/env bash
# Minimal zero-dependency test harness for the kit's shell scripts.
#
# Design: no framework, no install step — runs anywhere bash runs (Git Bash
# on Windows, ubuntu CI, inside a WSL distro). Suites are tests/test-*.sh
# files; each sources this lib, defines cases with t(), and ends with
# suite_done. External commands are faked at the PATH level (stub_cmd), so
# suites test the scripts' real CLI/lib contract without touching a system.
#
# Run everything via tests/run-tests.sh.

PASS=0
FAIL=0

# t <description> <command...> — run command as a test case, report PASS/FAIL.
t() {
  local desc="$1"; shift
  if "$@"; then
    PASS=$((PASS + 1))
    printf '  PASS  %s\n' "$desc"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s\n' "$desc"
  fi
}

assert_eq() { # assert_eq <expected> <actual>
  if [[ "$1" != "$2" ]]; then
    printf '    expected [%s], got [%s]\n' "$1" "$2"
    return 1
  fi
}

assert_contains() { # assert_contains <haystack> <needle>
  if [[ "$1" != *"$2"* ]]; then
    printf '    [%s] does not contain [%s]\n' "$1" "$2"
    return 1
  fi
}

# --- PATH-level command stubbing ---------------------------------------------
# sandbox_new creates a temp dir; stub_cmd places a fake command there that
# logs its arguments and emits a canned stdout / exit code. sandbox_path
# prepends it to PATH so sourced script code resolves the stub first.

SB_BIN=""
SB_LOG=""

sandbox_new() {
  local dir; dir="$(mktemp -d)"
  SB_BIN="$dir/bin"
  SB_LOG="$dir/commands.log"
  mkdir -p "$SB_BIN"
  : > "$SB_LOG"
  export SB_LOG
}

sandbox_path() { PATH="$SB_BIN:$PATH"; }

sandbox_calls() { cat "$SB_LOG"; }          # every stub invocation so far
sandbox_reset() { : > "$SB_LOG"; }          # clear the invocation log

# stub_cmd <name> <stdout> [exit_code]
stub_cmd() {
  local name="$1" out="${2:-}" code="${3:-0}"
  cat > "$SB_BIN/$name" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$name \$*" >> "\$STUB_LOG"
printf '%s\n' "$out"
exit $code
EOF
  chmod +x "$SB_BIN/$name"
}

# suite_done <name> — print the tally; non-zero exit marks the suite failed.
suite_done() {
  printf '  == %s: %d passed, %d failed\n' "$1" "$PASS" "$FAIL"
  [[ $FAIL -eq 0 ]]
}
