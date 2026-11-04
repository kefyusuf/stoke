# Node.js/TypeScript template (prod + dev targets)

A runnable sample wired for the kit's shared-cache pattern. Copy this directory
into your project (or copy the Dockerfile + .dockerignore into an existing repo
that already has `package.json`/`pnpm-lock.yaml`).

## What's inside

| File | Role |
|---|---|
| `Dockerfile` | 4 stages: `base → deps → dev/build → prod`. Lockfile-first, pnpm store as cache mount, non-root prod image |
| `docker-compose.yml` | `dev` service with bind mount + hot reload; `prod` under a profile |
| `.dockerignore` | Keeps `node_modules`/`dist`/`.git` out of the build context |
| `package.json`, `tsconfig.json`, `src/index.ts` | Minimal runnable sample — replace with your real code |

## Local use (inside WSL, repo on ext4)

```bash
docker compose up dev                 # hot reload on 127.0.0.1:3000
docker compose --profile prod up prod # compiled image on 127.0.0.1:3001
```

Prod/dev builds share the dependency layers — switching targets doesn't re-install.

## Shared cache (local ⇄ CI)

```bash
# with the kit's wrapper:
CACHE_REF=ghcr.io/org/myapp:buildcache IMAGE=ghcr.io/org/myapp:latest PUSH=1 \
  ../build.sh --target prod   # add --target to the buildx args or bake it in
```

Or point the CI templates in [`ci/`](../../ci/) at this Dockerfile — the
`cache-from/to type=registry,mode=max` pattern works unchanged; BuildKit caches
all four stages because of `mode=max`.

## Adapting to your project

1. Replace `src/`, `package.json`, `tsconfig.json` with your real code (keep
   `packageManager` in sync with the `corepack prepare` version in the Dockerfile).
2. Keep the order: manifest COPY → install → source COPY → build. That ordering
   *is* the cache strategy ([docs/cache-guide.md](../../docs/cache-guide.md)).
3. If you need extra runtime deps (native modules, openssl for Prisma, …), add
   them to the `prod` stage's base image, not the build stage.

Rust and Go variants follow the same skeleton (cargo target / GOCACHE as cache
mounts) — ask and they'll be added next.
