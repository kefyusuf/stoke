# FAQ / Troubleshooting

Türkçe: [faq.tr.md](faq.tr.md)

## Resources & Windows side

**Can I keep Docker Desktop installed?**
Yes — installed-but-idle (autostart off, WSL integration off) or in full parallel with
the kit's engine. Checklist, port rules and rollback: [migration.md](migration.md).

**Task Manager shows a huge `VMMEM` process.**
That *is* your WSL2 VM. It's capped by `.wslconfig` (`memory=`). If it's at the cap,
lower the cap; if the cap is high but VMMEM creeps up over days, ensure
`autoMemoryReclaim=gradual` (WSL 2.0+) or `wsl --shutdown` to reclaim immediately.

**Nothing changed after editing `.wslconfig`.**
It applies at VM start: run `wsl --shutdown` from PowerShell, then reopen the distro.
Also confirm the file is at `%UserProfile%\.wslconfig` (not inside the distro) and has
no BOM/encoding issues.

**`wsl --install` fails or the feature is missing.**
On older Windows 10 builds enable the features manually: `dism.exe /online /enable-feature
/featurename:Microsoft-Windows-Subsystem-Linux /all /norestart` and the same for
`VirtualMachinePlatform`, then reboot. Virtualization must be enabled in BIOS.

**Builds are mysteriously slow.**
Check `pwd`. Anything under `/mnt/c` crosses the 9P boundary (~5× slower —
[evidence #2](evidence.md#2-mntc-is-a-build-speed-trap-ext4-is-near-native)). Move the
clone into `~/work` and edit via VS Code Remote-WSL.

## Docker inside WSL

**`permission denied ... /var/run/docker.sock`.**
You're not in the `docker` group yet: `sudo usermod -aG docker $USER`, then close and
reopen the WSL terminal (or `newgrp docker`).

**`Cannot connect to the Docker daemon`.**
The service isn't running. With systemd enabled (`[boot] systemd=true` in `/etc/wsl.conf`,
then `wsl --shutdown`): `sudo systemctl enable --now docker`. Without systemd, start it
manually: `sudo service docker start`.

**Windows can't reach a container's published port, or localhost forwarding stopped.**
Restart WSL (`wsl --shutdown`) — the localhost relay re-establishes on boot. If you need
Windows→WSL reachability for the cache registry from another machine, that's a network
step beyond this kit (the local registry binds to 127.0.0.1 by design).

**Disk didn't shrink after deleting images.**
The ext4 virtual disk grows but doesn't auto-shrink unless `sparseVhd=true` (WSL 2.0+).
After big deletions: `docker system prune`, then from PowerShell
`wsl --manage <DistroName> --set-sparse true`.

## Cache & builds

**Second build is fast locally, but CI is always cold.**
Local and CI must use the *same* `CACHE_REF` registry and tag, and CI must be able to
authenticate to it (see the login step in each `ci/` template). Also confirm local
builds actually succeeded in pushing cache (`--cache-to` without errors).

**Cache hit never happens even with the same ref.**
The first *changed* instruction invalidates everything after it. The classic offender:
`COPY . .` above the dependency-install step. Reorder lockfile-first
([cache-guide.md](cache-guide.md#layer-order-beats-everything)).

**`--cache-to type=registry` fails with `unauthorized`.**
The export pushes cache *manifests* to the ref's registry — `docker login` to that
registry first (CI job included).

**Can I use `--cache-to type=registry` with `--load` (no push)?**
Yes — the cache export is independent of the image export. `templates/build.sh` does
exactly that when `PUSH=0`.

**The pull-through mirror isn't used.**
`registry-mirrors` in `/etc/docker/daemon.json` requires a daemon restart, only proxies
Docker Hub, and only serves tags someone already pulled through it
([registry-mirror.md](registry-mirror.md)).

**Need a mirror for multiple upstreams (ghcr.io, quay.io, …)?**
The stock pull-through cache proxies exactly one registry. For multi-upstream or
team-wide caching, graduate to [Harbor proxy cache](https://goharbor.io/docs/2.1.0/administration/configure-proxy-cache/)
or [docker-registry-proxy](https://github.com/rpardini/docker-registry-proxy) —
see the "Limits" section in [registry-mirror.md](registry-mirror.md).

**Where did the intermediate-stage cache go in CI?**
Default is `mode=min` (final stage only). This kit always sets `mode=max` — if you wrote
your own command, check the export flag.

## Script issues

**`setup-wsl.ps1` says it needs elevation.**
Run it from an *administrator* PowerShell — WSL feature installation needs it.

**`setup-engine.sh` fails on `apt-get update`.**
Docker's apt repo must match your distro codename (it derives from `/etc/os-release`).
Very old or non-Ubuntu/Debian distros aren't supported by that path — use the manual
steps in [setup-wsl2.md](setup-wsl2.md) adapted to your distro, or switch to Ubuntu.

**`verify.sh` registry step fails with port in use.**
It picks a random port in the 30000–49999 range; export `KIT_VERIFY_PORT=<port>` to
force a specific free one.
