# Security Policy

## Reporting a vulnerability

Please use **GitHub's private vulnerability reporting** (Security tab →
"Report a vulnerability") on this repository. Do not open a public issue for
security reports — several scripts in this kit perform system-level changes
and deserve a careful disclosure window.

## What this kit touches (review before running)

This kit is a set of **system-level automation scripts**. Before running
anything, read it — that is the intended workflow, not paranoia:

| Script | What it changes | Privilege |
|---|---|---|
| `setup/setup-wsl.ps1` | Windows features, `%UserProfile%\.wslconfig` (backs up existing) | Administrator |
| `setup/setup-engine.sh` | apt repositories + packages (Docker's official repo), `/etc/wsl.conf`, docker group, ownership record `/var/lib/stoke/ownership.env`; reuses a pre-existing engine | sudo |
| `setup/setup-nerdctl.sh` | apt packages, tarballs into `/usr/local`, systemd services | sudo |
| `setup/protect-distro.sh fix` | removes Desktop-injected files, masks units, creates a docker context | sudo |
| `setup/windows-context.ps1` | systemd drop-in in the distro: **unauthenticated** loopback-only TCP listener (127.0.0.1:2375) + Windows docker context `kit-wsl`; opt-in, `-Undo` reverses both | Administrator (Windows) / root (distro) |
| `setup/teardown.sh` | reverse of everything above, **ownership-aware**: only kit-created groups/packages/repo files are removed (pre-existing ones are kept); containers down, contexts + bridge drop-in removed, services off; `/var/lib/docker` and `.wslconfig` only with `--purge-data` / `--restore-wslconfig` | sudo |
| `cache-stack/*` | local Docker containers bound to `127.0.0.1` only | docker |

Hardening already built in:

- Every WSL-side script **refuses to run outside WSL2** (WSL1 gets the
  conversion command; native Linux needs the explicit `KIT_ALLOW_LINUX=1`
  override) — see `setup/lib/common.sh`, verified by tests.
- The setup and teardown scripts route every mutation through `kit_run`, show
  a plan and ask for consent first. `KIT_DRY_RUN=1` (or `--dry-run`) prints
  every change and executes nothing; `KIT_YES=1` (or `--yes`) runs unattended.
  Exceptions: `protect-distro.sh fix` honors `KIT_DRY_RUN=1` (not the flag);
  `verify.sh` is a live benchmark and builds by design.
- `setup/teardown.sh` reverses every mutation in the table above (the
  Windows-side `kit-wsl` context via interop when a Windows docker CLI is
  reachable, otherwise it points at `windows-context.ps1 -Undo`), with data
  and config deletes strictly opt-in.
- **Ownership manifest**: `setup-engine.sh` snapshots the pre-install state
  (packages, docker group, membership, apt repo files) into
  `/var/lib/stoke/ownership.env` before mutating anything; a re-run never
  overwrites the original snapshot. `teardown.sh` parses it by allowlist
  (never sourced/eval'd) and reverses only what the kit created. Installs
  that predate the record get a warned full-reversal fallback.
- All downloaded tarballs are **sha256-pinned per architecture** and verified
  before extraction (`setup-nerdctl.sh`).
- apt packages come from **Docker's official signed repository only**.
- Every container image reference in this repo is **digest-pinned**.
- CI actions are **SHA-pinned**; Dependabot keeps pins fresh.
- Local registries bind to `127.0.0.1` (loopback) only.
- The kit's shell scripts are covered by a **unit test suite**
  (`tests/`, runs in CI) that stubs all external commands — the guard and
  mutation contracts cannot silently regress.

## Supported versions

| Version | Supported |
|---|---|
| latest tagged release | ✅ |
| `main` | ✅ (best effort) |
| older tags | ❌ upgrade |

## Scope

In scope: the scripts, Dockerfiles, CI templates and docs in this repository.
Out of scope: Docker/WSL/Windows themselves (report upstream), and anything
running *inside* containers built from the templates (that's the template
consumer's application).
