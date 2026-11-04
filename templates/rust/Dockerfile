# syntax=docker/dockerfile:1
# Rust template for wsl2-docker-cache-kit — prod + dev targets.
#
# Cache design (docs/cache-guide.md):
#   * dummy-crate deps stage compiles the whole dependency graph once; its
#     artifacts live in the SHARED target cache mount, so source edits rebuild
#     only your crate — locally and in CI (registry cache mode=max).
#   * cargo registry/git dirs are cache mounts too: no re-downloads.
# rust:1-alpine links against musl -> the prod binary runs on plain alpine.
ARG RUST_VERSION=1

FROM rust:${RUST_VERSION}-alpine AS base
WORKDIR /app

# --- deps: compile the dependency graph (the shared cache key) ------------------
FROM base AS deps
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN --mount=type=cache,id=cargo-registry,target=/usr/local/cargo/registry \
    --mount=type=cache,id=cargo-git,target=/usr/local/cargo/git \
    --mount=type=cache,id=cargo-target,target=/app/target \
    cargo build --release \
    # Drop the dummy's own binary so the real build can't mistake it for fresh
    # output (cargo freshness is mtime-based and COPY preserves old mtimes).
    && rm -f target/release/app target/release/deps/app-*

# --- dev: bind-mount your source (compose), cargo run ----------------------------
FROM deps AS dev
COPY . .
# Hot reload (optional): uncomment to add cargo-watch, then CMD below:
# RUN --mount=type=cache,id=cargo-registry,target=/usr/local/cargo/registry \
#     cargo install cargo-watch --locked
CMD ["cargo", "run"]

# --- build: real compile ----------------------------------------------------------
# Two hard-won rules:
#   1. cache-mount contents do NOT persist into the image layer — copy the
#      binary out of the mount into /out within the same RUN.
#   2. cargo freshness is mtime-based and COPY preserves old mtimes -> touch
#      the sources so cargo ALWAYS rebuilds the final crate (deps stay cached).
FROM deps AS build
COPY . .
RUN --mount=type=cache,id=cargo-registry,target=/usr/local/cargo/registry \
    --mount=type=cache,id=cargo-git,target=/usr/local/cargo/git \
    --mount=type=cache,id=cargo-target,target=/app/target \
    find src Cargo.toml -exec touch {} + \
    && cargo build --release \
    && mkdir -p /out && cp target/release/app /out/app

# --- prod: alpine + static binary, non-root ---------------------------------------
FROM alpine:3.20 AS prod
RUN apk add --no-cache ca-certificates
COPY --from=build /out/app /usr/local/bin/app
USER nobody
EXPOSE 3000
ENTRYPOINT ["/usr/local/bin/app"]
