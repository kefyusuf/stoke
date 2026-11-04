# Evidence

Every performance/licensing claim this kit makes, with sources. Numbers are third-party
measurements — they vary by machine and workload. `setup/verify.sh` reproduces the two
claims that matter most (cached build speedup and the registry cache round-trip) on *your*
hardware.

## Claims

### 1. Docker Desktop carries a heavy idle footprint; Engine-in-WSL2 is much lighter

- Docker Desktop with the WSL2 backend consumes roughly **2–3 GB of RAM just idling**;
  the `VMMEM` process holds ~2 GB after startup and does not release it.
  Sources: [Docker forums — idle memory usage](https://forums.docker.com/t/docker-desktop-idle-memory-usage/138540),
  [docker/for-win#12944](https://github.com/docker/for-win/issues/12944)
- Switching from Docker Desktop to a manual Docker Engine install inside WSL2 cut
  **resource usage roughly in half** and stopped background CPU wake-ups on an idle machine.
  Source: [XDA — running Docker through WSL instead of Docker Desktop](https://www.xda-developers.com/running-docker-through-wsl-instead-docker-desktop-cut-resource-usage-half)
- Without a `.wslconfig` limit, WSL2 may allocate **50–80% of host RAM**; capping it is the
  official mechanism. Source: [Microsoft — wsl-config](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)

### 2. `/mnt/c` is a build-speed trap; ext4 is near-native

- Benchmark: WSL2 ext4 performs close to native Linux, while NTFS access through `/mnt/c`
  is about **5× slower** (9P protocol boundary).
  Sources: [vxlabs WSL2 I/O measurements](https://vxlabs.com/2019/12/06/wsl2-io-measurements),
  [microsoft/WSL#4197](https://github.com/microsoft/WSL/issues/4197),
  [Stack Overflow — WSL slow with npm/yarn (9P)](https://stackoverflow.com/questions/68972448/why-is-wsl-extremely-slow-when-compared-with-native-windows-npm-yarn-processing)
- Practical consequence: keep sources and the repo clone inside the distro (`~/work`),
  edit from Windows via VS Code Remote-WSL.

### 3. `.wslconfig` is the official resource cap

- `memory`, `processors`, `swap` under `[wsl2]`; applied after `wsl --shutdown`.
  Source: [Microsoft — advanced WSL settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)
- Newer WSL builds additionally offer `autoMemoryReclaim` and `sparseVhd` under
  `[experimental]` to return idle cached memory and shrink the ext4 disk file.

### 4. BuildKit registry cache shares layers between machines — `mode=max` is the key

- Official cache storage backends (`type=registry|gha|s3|local|…`) and how `cache-from` /
  `cache-to` compose. Source: [Docker docs — cache storage backends](https://docs.docker.com/build/cache/backends)
- `mode=min` (default) exports only the final image's layers; `mode=max` exports **all
  intermediate stages**, which is what multi-stage builds need for cross-machine reuse.
  Sources: [BuildKit docs — cache modes](https://crazymax.dev/buildkit/usage/cache),
  [moby/buildkit#1515](https://github.com/moby/buildkit/issues/1515)
- CI guide for the same mechanism: [GitLab — Docker layer caching](https://docs.gitlab.com/ci/docker/docker_layer_caching/)

### 5. Pull-through mirror deduplicates base images — with honest limits

- Official registry can run as a pull-through cache via `proxy.remoteurl`; clients opt in
  with `registry-mirrors`. Source: [Docker docs — mirror the Docker Hub library](https://docs.docker.com/docker-hub/image-library/mirror/)
- Limits: **read-only**, **single upstream**, effective for Docker Hub-style registries;
  caches only what is pulled through it. Multi-upstream needs e.g.
  [Harbor proxy cache](https://goharbor.io/docs/2.1.0/administration/configure-proxy-cache/)
  or [docker-registry-proxy](https://github.com/rpardini/docker-registry-proxy).

### 6. Licensing: Docker Engine removes Docker Desktop's per-seat cost pressure

- Docker Desktop requires a paid subscription for professional use in organizations with
  **more than 250 employees OR more than $10M annual revenue** (either condition triggers it).
  Source: [Docker — Desktop license agreement](https://docs.docker.com/subscription-billing/desktop-license/),
  [Docker pricing](https://www.docker.com/pricing/)
- Docker Engine itself is Apache-2.0 and unrestricted; this kit never installs Docker Desktop.

### 7. containerd + nerdctl is the lighter optional path

- nerdctl is a Docker-compatible CLI over containerd (Kubernetes' default runtime since the
  dockershim removal). Sources: [nerdctl guide](https://jacar.es/en/nerdctl-a-lightweight-docker-alternative-over-containerd),
  [containerd alternatives overview](https://www.qovery.com/blog/4-best-docker-desktop-alternatives)
- Kept as an optional variant in this kit because Docker CLI/buildx compatibility is broader:
  [docs/nerdctl-variant.md](nerdctl-variant.md)

### 8. Dependency caches: cache the store, not `node_modules`

- pnpm's official CI guidance: cache the **pnpm store** (path via `pnpm store path`),
  keyed on the lockfile hash; `node_modules` holds hard links into the store and is
  ineffective/fragile to cache. Sources: [pnpm — CI](https://pnpm.io/continuous-integration),
  [pnpm discussion #6374](https://github.com/orgs/pnpm/discussions/6374)
- General: key cache entries on lockfile hashes, use `--frozen-lockfile` in CI.

## This kit's own measurements

Recorded 2026-11-04 on the kit author's machine — **Windows 11 host, WSL2 Ubuntu-24.04
distro, Docker Engine 29.9.3 inside the distro**. Single machine, indicative numbers;
rerun `setup/verify.sh` on yours and compare.

| What | Result |
|---|---|
| `verify.sh` layer-cache speedup | **7×** — warm build 1.3 s vs cold build (incl. base pull) |
| `verify.sh` registry round trip | Builder B (fresh, empty store) hit **CACHED** via `--cache-from` — tested twice: under Docker Desktop 29.9.2 and under the in-distro Engine 29.9.3 |
| Stack templates | **node-ts, rust, go: all 6 targets (prod+dev) built; 3 prod containers answered HTTP 200** in the WSL engine |
| Real migration | Docker Desktop → Engine-in-WSL2 performed live; both engines ran in parallel during the overlap |
| Bugs the live runs caught | Rust dummy-binary mtime trap (silent stale binary — exit 0, no server) and the cache-mount-does-not-persist trap; both fixed in the templates |

## Self-verification

```bash
./setup/verify.sh
```

1. Builds a small image twice and reports the speedup (layer cache hit).
2. Pushes cache to a throwaway local registry, then rebuilds from a *fresh* BuildKit
   builder pulling `cache-from` from that registry — proving cross-builder (local ⇄ CI)
   cache reuse works on your machine.

For the RAM claim, compare Task Manager's `VMMEM` before/after uninstalling Docker
Desktop with this kit — and set the cap in `.wslconfig` regardless.

## Caveats

- Third-party numbers above are indicative, not guarantees; disk speed, project size and
  network matter. Treat them as reasons to try, then measure with `verify.sh`.
- First-ever build is always cold; the wins show from the second build onward.
- CI cache pulls consume network bandwidth; large `mode=max` caches make the first CI
  build of a new branch slower and subsequent ones faster.
