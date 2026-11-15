# Living with Docker Desktop (migration & coexistence)

Türkçe: [migration.tr.md](migration.tr.md)

Short answer first: **you do not have to uninstall Docker Desktop to use this kit.**
The kit's goal is a lighter machine — uninstalling is only the *final* step of that
goal, and it is yours to make (or postpone indefinitely). Three honest options:

| Option | Resource cost | Pick when |
|---|---|---|
| **A. Installed but idle** (Desktop never runs) | ~2–3 GB disk, no RAM/CPU | You want most of the win with zero risk — the balanced default |
| **B. Full parallel** (both engines running) | Both engines' RAM while both are up | You need Desktop's GUI/Kubernetes toggle *and* the kit engine daily |
| **C. Uninstall** | Full RAM recovery | Weeks of Option A/B felt solid; measured VMMEM drop confirms |

## Option A — installed but idle (checklist)

1. Docker Desktop → Settings → General → **uncheck "Start Docker Desktop when you
   sign in"** (the default is ON — without this it silently runs anyway).
2. Settings → Resources → **WSL Integration → your kit distro OFF**. If left on,
   Desktop injects its own socket into the distro and the kit's independent engine
   can get shadowed.
3. Reboot, then verify: `wsl -l -v` → `docker-desktop` shows **Stopped**. That's the
   whole cost: zero.
4. What changes day-to-day: the Windows-side `docker` CLI belongs to Desktop, so with
   Desktop stopped it prints "cannot connect". Your engine lives in the distro:
   ```powershell
   wsl -d Ubuntu-24.04 -- docker ps      # from PowerShell
   ```
   or just open the distro terminal and use `docker` there as usual.

### Enforced isolation — beyond the GUI toggle

The two toggles above are Desktop-side settings: a Desktop update, a reinstall, or a
teammate sharing the machine can silently flip them back. `setup/protect-distro.sh`
guards the *distro side* instead — run `check` after engine setup and after any
Desktop update:

```bash
./setup/protect-distro.sh check     # who owns the CLI and the socket? exit≠0 on injection
./setup/protect-distro.sh fix       # root: clean Desktop artifacts + pin the context
```

It detects all three injection mechanisms (CLI shadowing via `/usr/local/bin`
symlinks into `/mnt/wsl/docker-desktop`, socket hijacking of `/var/run/docker.sock`,
and the `docker-desktop-proxy` systemd unit), removes them, and pins the user's
default docker **context** to the local socket — so even a re-injected Desktop CLI
would still talk to the kit's engine. Fix is reversible: re-enable WSL Integration
in Desktop and `systemctl unmask <unit>` if you ever *want* Desktop's engine here.

## Option B — full parallel (both engines at once)

This is verified working (Windows CLI → Desktop engine; distro CLI → the kit's
engine, independent daemons, separate image stores). One hard rule and one habit:

- **The rule: never publish the same Windows-side port from both engines.** Both
  forward to Windows localhost, so `127.0.0.1:5000` in Desktop *and* in the WSL
  engine collide. All compose files in this kit bind `127.0.0.1` and carry this note.
- The habit: know *which* engine you're talking to. Windows-side `docker` → Desktop.
  Inside the distro → the kit engine. `docker context ls` on each side shows it.

## Option C — uninstall

- **When**: after a few weeks on Option A/B, compare Task Manager's `VMMEM` with
  Desktop running vs. stopped — decide with data.
- **How**: Windows Apps → uninstall *Docker Desktop only*. Your distro, the kit's
  engine, and everything in `~/work` are untouched (images live in the distro's
  engine store, not Desktop's).
- **Rollback**: reinstall any time. Nothing in this kit depends on Desktop being
  absent.

## Removing the kit itself

`./setup/teardown.sh` reverses every kit mutation in safe order (containers ->
docker context -> services -> group -> packages -> apt repo files). Preview it
with `--dry-run`; the docker data root and `.wslconfig` are only touched with
explicit `--purge-data` / `--restore-wslconfig`. The full touch table lives in
[SECURITY.md](../SECURITY.md).

## What is shared vs. separate

| | Docker Desktop engine | Kit engine (in distro) |
|---|---|---|
| Images, containers, volumes | its own store | its own store |
| Build cache | its own builder state | its own builder state |
| Shared BuildKit registry cache ref (`CACHE_REF`) | **shared** (it's a registry) | **shared** |
| Project sources on ext4 | shared (same files) | shared |

Engines don't share local state — if you build in one, the other stays cold *locally*;
the registry cache ref is the bridge between them (and with CI).

Related: [faq.md](faq.md) · [setup-wsl2.md](setup-wsl2.md) · [cache-guide.md](cache-guide.md)
