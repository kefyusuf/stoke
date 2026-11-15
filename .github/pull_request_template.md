<!-- PR: one logical change. CI must pass before merge (see CONTRIBUTING.md). -->

## What & why

<!-- What does this change, and why? Link the issue if there is one: Closes #... -->

## Checklist

- [ ] `bash tests/run-tests.sh` passes locally (extend the suites if behavior changed)
- [ ] Mutations go through `kit_run` / `kit_consent` — new system changes are dry-run-able and reversible via teardown
- [ ] shellcheck-clean at `--severity=style` (`setup/*.sh setup/lib/*.sh templates/build.sh`)
- [ ] Docs updated bilingually if user-facing (README/docs EN + TR)
- [ ] Any new external dependency is pinned (digest/sha256/SHA) and Dependabot-aware
- [ ] Claims got sources (`docs/evidence.md`) if performance/licensing related

## Verification

<!-- How did you prove it? e.g. "./setup/verify.sh output", before/after of doctor, test names -->
