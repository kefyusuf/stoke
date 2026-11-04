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
| `setup/setup-engine.sh` | apt repositories + packages (Docker's official repo), `/etc/wsl.conf`, docker group | sudo |
| `setup/setup-nerdctl.sh` | apt packages, tarballs into `/usr/local`, systemd services | sudo |
| `setup/protect-distro.sh fix` | removes Desktop-injected files, masks units, creates a docker context | sudo |
| `cache-stack/*` | local Docker containers bound to `127.0.0.1` only | docker |

Hardening already built in:

- All downloaded tarballs are **sha256-pinned per architecture** and verified
  before extraction (`setup-nerdctl.sh`).
- apt packages come from **Docker's official signed repository only**.
- Every container image reference in this repo is **digest-pinned**.
- CI actions are **SHA-pinned**; Dependabot keeps pins fresh.
- Local registries bind to `127.0.0.1` (loopback) only.

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
