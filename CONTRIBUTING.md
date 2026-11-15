# Contributing

Thanks for considering a contribution! The kit is small on purpose — read
[docs/evidence.md](docs/evidence.md) for the "why" behind every pattern before
changing one.

## Local development

```bash
# inside WSL, repo cloned to the distro filesystem (NOT /mnt/c):
./setup/setup-engine.sh          # once
./setup/verify.sh                # proves the cache loop on your machine
./setup/protect-distro.sh check  # if Docker Desktop coexists
bash tests/run-tests.sh          # unit suites for the script contracts
```

CI runs on every push: shellcheck (style severity), `bash -n`, the unit test
suites, YAML parse, markdown link check, a gitleaks secret scan, and a real
build + HTTP smoke of every template — mirror that locally before opening a PR:

```bash
# (Git Bash on Windows: prefix the docker line with MSYS_NO_PATHCONV=1
#  and use -v "$(pwd -W):/wk")
docker run --rm -v "$PWD:/wk" -w /wk koalaman/shellcheck:stable \
  --severity=style --external-sources --source-path=SCRIPTDIR \
  setup/setup-engine.sh setup/setup-nerdctl.sh setup/protect-distro.sh \
  setup/verify.sh setup/teardown.sh setup/doctor.sh setup/init-project.sh \
  setup/lib/common.sh templates/build.sh
for f in setup/*.sh setup/lib/*.sh templates/build.sh; do bash -n "$f"; done
bash tests/run-tests.sh
```

## Nightly E2E triage

The `windows-e2e` workflow runs every night (04:00 UTC) on a real Windows
runner. A red run is a **signal, not a crisis** — triage by which step failed:

| Failed step | Meaning | Typical fix |
|---|---|---|
| Install WSL2 + Ubuntu-22.04 | runner image / WSL action drift | bump the action pin; almost never a kit change |
| Copy repo into the distro | runner networking / pwsh path math | inspect that step's snippet; unit tests already passed |
| `setup-engine.sh` | upstream apt/Docker drift **or** kit regression | check Docker repo availability; run the unit suites |
| `verify.sh` | kit regression in the cache path | bisect against the last green nightly |
| `teardown.sh` | regression in the reversal path | treat as release-blocking |

After the fix, re-dispatch: `gh workflow run windows-e2e.yml`.

## Adding a stack template

The three shipped templates (`node-ts`, `rust`, `go`) are one skeleton in three
dialects. A new template must:

1. **Live in `templates/<stack>/`** with: `Dockerfile`, `docker-compose.yml`
   (dev target + prod profile), `.dockerignore`, a **minimal runnable sample**
   (with a committed lockfile — `pnpm-lock.yaml` / `Cargo.lock` / `go.sum` so it
   builds as-shipped), and a README.
2. **Put dependencies in a LAYER, not (only) a cache mount.** Layer cache is
   what `--cache-to type=registry,mode=max` exports to fresh CI builders.
   Cache mounts are builder-local — use them for download dirs (pnpm store,
   cargo registry) but never for anything a later stage consumes.
3. **Copy final artifacts out of any cache mount** in the same `RUN` (e.g.
   `cp target/release/app /out/app`). Mounts do not persist into image layers.
4. **Defeat mtime-based freshness** when a dummy-crate/stub pattern is used:
   `find src ... -exec touch {} +` before the real build, and drop the stub's
   own binary in the deps stage — otherwise a silent stale binary ships
   (see the comments in `templates/rust/Dockerfile` — both traps were caught
   by live runs).
5. **Be non-root in the final stage**, and add a `HEALTHCHECK` if the base
   image can execute one. `FROM scratch` cannot — document that honestly
   (see `templates/go/Dockerfile`).
6. **Digest-pin base images** (`tag@sha256:...`) and note the bump procedure.
   Dependabot's `docker` ecosystem then keeps pins fresh — add your directory
   to `.github/dependabot.yml`.
7. **Note the parallel-engine port caveat** in the compose file.
8. **Wire it in**: add `template` + directory entries to
   `.github/workflows/ci.yml` (build matrix + smoke) and `.github/dependabot.yml`.
9. **Prove it before the PR**: build both targets, run the prod container,
   `curl` it. If a live run catches a gotcha, document it in the Dockerfile
   comments and (if generally interesting) in `docs/evidence.md`.
10. **Document bilingually** if it is a docs page; template READMEs may start
    English-only, but the main guides carry TR mirrors.

## Style

- Bash: `set -euo pipefail`, everything quoted, shellcheck-clean at
  `--severity=style`, `trap` cleanup for anything created.
- Mutations go through `kit_run`, consent through `kit_consent`
  (`setup/lib/common.sh`) — a script that changes system state must support
  `--dry-run` and ask before its first change. The unit suites in `tests/`
  pin these contracts; extend them when you change a script's behavior.
- Versions/checksums pinned with an override escape hatch (see
  `setup/setup-nerdctl.sh`).
- Claims get sources: performance/licensing statements belong in
  `docs/evidence.md` with links, not in commit messages.

## Commit messages

Short imperative subject, body explaining *why* when it isn't obvious.
CI must pass before merge.
