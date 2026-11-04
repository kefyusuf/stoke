# Go template (prod + dev targets)

Runnable sample wired for the kit's shared-cache pattern. Copy this directory
into your project (or just the `Dockerfile` + `.dockerignore` into an existing
module that already has `go.mod`).

## What's inside

| File | Role |
|---|---|
| `Dockerfile` | `base → deps → dev/build → prod` — GOMODCACHE + GOCACHE cache mounts, `CGO_ENABLED=0`, `scratch` prod stage, non-root |
| `docker-compose.yml` | `dev` with bind mount + persisted mod/build cache volumes; `prod` under a profile |
| `.dockerignore` | Keeps caches and `.git` out of the context |
| `go.mod`, `main.go` | Minimal runnable sample (std-only HTTP with server timeouts) — replace with your real code |

## Local use (inside WSL, repo on ext4)

```bash
docker compose up dev                   # go run on 127.0.0.1:3000
docker compose --profile prod up prod   # scratch binary on 127.0.0.1:3001
```

## Shared cache (local ⇄ CI)

Point the CI templates in [`ci/`](../../ci/) at this Dockerfile —
`cache-from/to type=registry,mode=max` carries all stages between machines.

## Adapting to your project

1. Replace `main.go` with your code; add your `go.sum` (the Dockerfile's
   `go.sum*` glob tolerates modules without one, like this sample).
2. `USER 65534` (nobody) in `scratch` — if you need a different uid, pass a
   number; scratch has no /etc/passwd for names.
3. Hot reload: uncomment the Air install in the dev stage and adjust the
   compose command.

Node/TS and Rust variants share the same skeleton — see `templates/node-ts/`,
`templates/rust/`.
