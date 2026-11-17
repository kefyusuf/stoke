# Build cache guide

How the shared cache works, and how to wire it correctly for your project.

Reference: [Docker — cache storage backends](https://docs.docker.com/build/cache/backends).

## Mental model

BuildKit stores layers content-addressed: a layer's identity is a hash of its inputs
(base image + files copied + command). If nothing a step depends on changed, its cached
layer is reused — *if the cache is reachable*. This kit makes it reachable in two ways:

1. **Local store** — the daemon keeps cache on disk; second local build is fast.
2. **Shared registry ref** — `cache-from`/`cache-to type=registry` push/pull cache
   manifests to a Docker registry. Any machine that can reach the registry — your WSL2
   box, a CI runner, a teammate — warms or reuses the same cache.

`templates/build.sh` wraps this in one command:

```bash
CACHE_REF=127.0.0.1:5000/myapp:buildcache ./build.sh            # local registry
CACHE_REF=ghcr.io/org/myapp:buildcache PUSH=1 ./build.sh        # CI-shared
```

Equivalent raw command:

```bash
docker buildx build \
  --cache-from type=registry,ref="$CACHE_REF" \
  --cache-to   type=registry,ref="$CACHE_REF",mode=max \
  --push -t "$IMAGE" .
```

## `mode=min` vs `mode=max`

| | `mode=min` (default) | `mode=max` |
|---|---|---|
| Exports | layers of the **final stage** only | **all stages**, including intermediates |
| Multi-stage cross-machine reuse | mostly misses | full reuse |
| Cache size in registry | small | larger |
| Use when | single-stage Dockerfile | multi-stage (the common case) — **this kit's default** |

Source: [BuildKit — cache modes](https://crazymax.dev/buildkit/usage/cache/).

## Layer order beats everything

The cache is invalidated top-down from the first changed instruction. The classic miss:
`COPY . .` *before* `RUN <install dependencies>` — any source edit re-downloads and
re-installs all dependencies. The fix is a lockfile-first ordering:

```dockerfile
COPY package.json pnpm-lock.yaml ./     # cache key = manifests only
RUN --mount=type=cache,target=/root/.local-share-pnpm \
    pnpm install --frozen-lockfile
COPY . .                                # source edits only invalidate from here
RUN pnpm build
```

`templates/Dockerfile` ships this skeleton with TODO markers for your real commands.

## Cache mounts vs layers

For anything that writes a large cache dir (package managers, compilers), prefer a
**cache mount** over baking the dir into a layer:

```dockerfile
RUN --mount=type=cache,target=/root/.cache \
    pip install -r requirements.txt
```

- The cache dir persists between builds **on the same builder** without bloating the image
  or the registry cache.
- Caveat: cache mounts are builder-local — they are *not* exported by `cache-to`. They
  speed up local rebuilds and self-hosted runners; cross-machine reuse still comes from
  the layer cache. Both mechanisms complement each other.

## Dependency stores

- Cache the **store**, not `node_modules`/`venv` — e.g. pnpm's store holds the packages
  and `node_modules` hard-links into it ([pnpm CI docs](https://pnpm.io/continuous-integration)).
- In CI without Docker, use the platform cache: `actions/setup-node` with `cache: pnpm`
  (GitHub), `cache:` with lockfile key (GitLab).

## Wiring CI

| File | Mechanism |
|---|---|
| [`ci/github-actions.yml`](../ci/github-actions.yml) | `type=registry` against GHCR — the platform-independent pattern; works for GitLab registry/others by swapping the ref |
| [`ci/github-actions-gha.yml`](../ci/github-actions-gha.yml) | `type=gha` — GitHub's built-in cache backend; no registry needed, but **GitHub-only** (10 GB per-repo cache quota, evicted LRU) |
| [`ci/gitlab-ci.yml`](../ci/gitlab-ci.yml) | `type=registry` against the GitLab container registry with docker:dind |

Local and CI **must share the same ref** for the handoff to work — that's the whole point.

## Cache trust policy

**Cache write access is a trust boundary.** BuildKit trusts the layers it imports:
content-addressing keys a layer by its *inputs*, not by who produced it. Anyone who
can write to the cache ref can export crafted layers that later builds will reuse.
"Who may `cache-to`?" matters as much as "who may push the image?".

The kit's policy — **one trusted writer per shared ref**:

| Context | Reads (`cache-from`) | Writes (`cache-to`) |
|---|---|---|
| Local dev (`build.sh` / `build.ps1`) | yes | yes — your machine, your registry credentials |
| CI, default branch | yes | **yes — the only CI writer** |
| CI, pull request / merge request | yes | **no** (registry backend) |

- `ci/github-actions.yml` and `ci/gitlab-ci.yml` implement this literally: the
  PR/MR job imports only; the default-branch job refreshes `:buildcache`. A broken
  or hostile PR can never poison the shared cache.
- Fork PRs additionally cannot even *read* a private GHCR cache manifest (their
  `GITHUB_TOKEN` is read-only and scoped to the fork) — they build cold.
- The wrappers always export (`mode=max`): they are **trusted-local tools**. Run
  them only on checkouts you trust; never hand shared-ref write credentials to
  untrusted code.

### GitHub-native cache (`type=gha`) is different

GitHub's cache service isolates writes per branch, so the gha template safely
exports on PRs too:

- A regular `pull_request` run (merge ref) reads the base/default-branch cache but
  writes only its **own branch scope** — it can never refresh the default branch's
  cache. Fork PRs get their own isolated scope.
- **Read-only triggers**: `issue_comment`, `pull_request_target`, and
  `pull_request` with `types: [closed]` run in the default-branch context with
  read-only cache access — `cache-to` fails there ("failed to reserve cache").
  Keep `cache-from`, omit `cache-to` (or set `ignore-error=true`), and let the
  default-branch push populate the cache.
- The **default scope is `buildkit`**: two images built in one repo overwrite each
  other's cache. Give each image its own `scope=<name>` (this repo's CI uses
  `scope=kit-<template>-<target>`).

Sources: [Docker — GHA cache backend](https://docs.docker.com/build/cache/backends/gha/),
[Docker — cache write restrictions](https://docs.docker.com/build/ci/github-actions/cache/#cache-write-restrictions).

## Cache hygiene

- The shared ref grows over time; periodically re-create it from a clean builder or point
  CI at a rotating ref (`buildcache-$(date +%Y-%m)`) and delete stale ones.
- Registry GC (`registry` garbage-collect) reclaims deleted-manifest space on self-hosted
  registries.
- Local prune when disk fills: `docker builder prune` (add `-f` in scripts, never in docs 🙂).

## Troubleshooting misses

| Symptom | Usual cause |
|---|---|
| CI always cold | `cache-from` ref differs from what local pushed; or registry auth missing |
| Local build slow again after edits | a step above the dependency install changes (see *Layer order*) |
| `mode=max` set but intermediates missing in CI | typo in `--cache-to` (it's the *export* side that decides) |
| Works locally, fails in CI push | the ref registry requires auth/login in that job |
