#!/usr/bin/env bash
# Runs every tests/test-*.sh suite; exits non-zero if any suite failed.
# Designed for both local TDD loops and the CI lint job.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."

rc_total=0
found=0
for suite in tests/test-*.sh; do
  [[ -e "$suite" ]] || continue
  found=$((found + 1))
  echo "== $suite"
  if bash "$suite"; then :; else rc_total=1; fi
done

if [[ $found -eq 0 ]]; then
  echo "no test suites found (tests/test-*.sh)"
  exit 1
fi
if [[ $rc_total -eq 0 ]]; then
  echo "ALL SUITES PASSED ($found)"
else
  echo "SUITE FAILURES - see above"
fi
exit $rc_total
