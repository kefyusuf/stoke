# Changelog

All notable changes to stoke. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are semver-ish
(the kit is scripts + templates, so "breaking" = a template/setup contract change).

## [1.0.0] - 2026-11-15

First public release.

### Added

- `setup/doctor.sh`: one-pass read-only health report (daemon, buildx,
  context, systemd, Desktop CLI shadowing, cache stack containers, mirror
  registration, disk usage). FAIL-grade problems exit 1; optional pieces
  warn. `setup-engine.sh` chains a best-effort protect-distro check.
- `setup/init-project.sh <stack> <name>`: project scaffolder - stack
  template + cache wrappers + project-scoped `.env`
  (`CACHE_REF=127.0.0.1:5000/<name>:buildcache`). Kit mutation policy
  applies (--dry-run / consent / --yes).
- Project-aware build wrappers: `build.sh`/`build.ps1` default
  `CACHE_REF` to `127.0.0.1:5000/<dir>:buildcache` (projects no longer
  share one "myapp" ref), read a allowlisted-literal `.env` layer
  (never eval'd), and pass extra buildx args through (`--` / `-ExtraArgs`).
- `setup/windows-context.ps1`: bridge the in-distro engine to Windows
  tools (loopback-only TCP listener + `kit-wsl` docker context, `-Undo`
  included); unblocks PowerShell CLI, VS Code Docker panel, Visual Studio.
- Kit-wide mutation policy (`setup/lib/common.sh`): every script supports
  `--dry-run`/`KIT_DRY_RUN=1` (preview, executes nothing) and
  `--yes`/`KIT_YES=1` (unattended); interactive runs print their plan and ask
  `[y/N]` before the first change
- WSL2 platform guard: all WSL-side scripts refuse WSL1 (with the conversion
  command) and non-WSL hosts; explicit `KIT_ALLOW_LINUX=1` override
- `setup/teardown.sh`: scripted, order-safe reversal of every kit mutation;
  `/var/lib/docker` and `.wslconfig` are only touched with explicit
  `--purge-data` / `--restore-wslconfig`; `wsl --unregister` deliberately not
  automated
- `tests/`: zero-dependency bash test harness; 71 unit tests covering the
  guard / dry-run / consent / teardown contracts, wired into CI
- CI: unit-test step, gitleaks full-history secret scan, `windows-e2e.yml`
  (nightly + on-demand real-WSL2 run on a Windows runner: setup -> verify ->
  teardown)

### Fixed

- `USER` unbound crash under `set -u` in minimal shells (SUDO_USER -> USER ->
  `id -un` fallback chain in all scripts)
- Dry-run notices were swallowed by call-site redirects (`> /dev/null`,
  `2>/dev/null || true`) — notices now go to fd 3
- SIGPIPE (rc 141) when piping into `kit_run ... tee` in dry-run mode; file
  writes use the herestring pattern (documented in the lib)

## 0.1.0 - 2026-11-05 (pre-public history)

First public release.

### Added

- WSL2 + Docker Engine local setup (PowerShell + bash, no Docker Desktop):
  `setup/setup-wsl.ps1`, `setup/setup-engine.sh`, `.wslconfig.template`
- Optional lighter runtime: `setup/setup-nerdctl.sh` (containerd + nerdctl +
  BuildKit, sha256-pinned tarballs per architecture)
- Shared build cache: `templates/build.sh` / `build.ps1` wrapping
  `buildx --cache-from/to type=registry,mode=max` (local ⇄ CI warm each other)
- Local cache registry + Docker Hub pull-through mirror (`cache-stack/`, both
  healthchecked, digest-pinned)
- Stack templates with prod + dev targets, all CI-built and HTTP-smoked:
  `templates/node-ts/`, `templates/rust/`, `templates/go/`
- CI templates: GitHub Actions (registry + gha cache backends) and GitLab CI
- Distrowatch: `setup/protect-distro.sh` — detects and cleans Docker Desktop's
  WSL-integration injection; pins the default docker context to the kit engine
- Proof tooling: `setup/verify.sh` (cold/warm build timing + fresh-builder
  registry cache round trip) and `docs/evidence.md` with sourced claims +
  this kit's own measurements
- Bilingual docs (EN + TR): README, evidence, setup, cache guide, migration &
  coexistence, registry mirror, nerdctl variant, FAQ
- Repo CI (shellcheck, bash -n, YAML parse, link check, template build matrix
  with smoke) and Dependabot for pinned actions/images

### Notes

- Scripts perform system-level changes — review before running
  ([SECURITY.md](SECURITY.md))
- Docker Desktop can stay installed (idle or parallel) — see
  [docs/migration.md](docs/migration.md)

[1.0.0]: https://github.com/kefyusuf/stoke/releases/tag/v1.0.0
