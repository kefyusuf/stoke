# Changelog

All notable changes to wsl2-docker-cache-kit. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are semver-ish
(the kit is scripts + templates, so "breaking" = a template/setup contract change).

## [0.1.0] - 2026-11-05

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

[0.1.0]: https://github.com/<owner>/wsl2-docker-cache-kit/releases/tag/v0.1.0
