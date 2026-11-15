# syntax=docker/dockerfile:1
# Rust template for stoke — prod + dev targets.
#
# Cache design (docs/cache-guide.md):
#   * deps stage compiles the dependency graph INTO AN IMAGE LAYER (dummy crate
#     trick). Layer cache IS exported by `--cache-to type=registry,mode=max`,
#     so a fresh CI builder reuses the compiled deps; source edits rebuild only
#     your crate — locally AND in CI. Trade-off: the registry cache grows by
#     the size of the compiled dep graph (the price of real cross-machine reuse).
#   * cargo registry/git stay as cache mounts for fast local re-downloads;
#     mounts are builder-local and intentionally NOT exported.
#   * rust:1-alpine links against musl -> the prod binary runs on plain alpine.

# Pinned (supply-chain hardening): bump tag+digest together via
# `docker buildx imagetools inspect rust:1-alpine`.
FROM rust:1-alpine@sha256:27cd9befd4a05d6f6eb407c3e28365f5092f008bfc5946207cca76ae5179ef23 AS base
WORKDIR /app

# --- deps: compile the dependency graph INTO THE LAYER (the shared cache key) --
FROM base AS deps
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN --mount=type=cache,id=cargo-registry,target=/usr/local/cargo/registry \
    --mount=type=cache,id=cargo-git,target=/usr/local/cargo/git \
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
#   1. cargo freshness is mtime-based and COPY preserves old mtimes -> touch the
#      sources so cargo ALWAYS rebuilds the final crate (deps come from the layer).
#   2. outputs needed by later stages must be written OUTSIDE any cache mount —
#      mounts do not persist into image layers.
FROM deps AS build
COPY . .
RUN find src Cargo.toml -exec touch {} + \
    && cargo build --release \
    && mkdir -p /out && cp target/release/app /out/app

# --- prod: alpine + static binary, non-root ---------------------------------------
# Pinned (supply-chain hardening): bump tag+digest together via
# `docker buildx imagetools inspect alpine:3.20`.
FROM alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf AS prod
RUN apk add --no-cache ca-certificates
COPY --from=build /out/app /usr/local/bin/app
USER nobody
EXPOSE 3000
ENTRYPOINT ["/usr/local/bin/app"]
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${PORT:-3000}/" >/dev/null 2>&1 || exit 1
