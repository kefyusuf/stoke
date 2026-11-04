# Rust template (prod + dev targets)

Runnable sample wired for the kit's shared-cache pattern. Copy this directory
into your project (or just the `Dockerfile` + `.dockerignore` into an existing
crate that already has `Cargo.toml`/`Cargo.lock`).

## What's inside

| File | Role |
|---|---|
| `Dockerfile` | `base → deps (dummy crate) → dev/build → prod` — registry/git/target as cache mounts, musl static binary, non-root prod on alpine |
| `docker-compose.yml` | `dev` with bind mount + persisted target/registry volumes; `prod` under a profile |
| `.dockerignore` | Keeps `target/` out of the context |
| `Cargo.toml`, `src/main.rs` | Minimal runnable sample (tiny_http) — replace with your real crate |

## Why the dummy crate matters

The `deps` stage compiles your **dependency graph** against a `fn main() {}`
stub. Artifacts land in the shared `cargo-target` cache mount, so the real
build stage reuses them and source edits recompile only *your* code. In CI,
`mode=max` registry cache carries the same layers between machines — Rust's
biggest build-time win is exactly here.

## Local use (inside WSL, repo on ext4)

```bash
docker compose up dev                   # cargo run on 127.0.0.1:3000
docker compose --profile prod up prod   # static binary on 127.0.0.1:3001
```

## Shared cache (local ⇄ CI)

Point the CI templates in [`ci/`](../../ci/) at this Dockerfile —
`cache-from/to type=registry,mode=max` works unchanged across all stages.

## Adapting to your project

1. Replace `src/` and `Cargo.toml` deps; keep `[[bin]] name = "app"` in sync
   with the `COPY --from=build` path in the prod stage.
2. Keep the dummy-crate deps stage — it *is* the cache strategy for Rust.
3. Hot reload: uncomment the `cargo-watch` line in the dev stage, change the
   compose dev command accordingly.

Node/TS and Go variants share the same skeleton — see `templates/node-ts/`,
`templates/go/`.
