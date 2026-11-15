# syntax=docker/dockerfile:1
# Go template for stoke — prod + dev targets.
#
# Cache design (docs/cache-guide.md):
#   * deps stage runs `go mod download` INTO AN IMAGE LAYER — layer cache IS
#     exported by `--cache-to type=registry,mode=max`, so a fresh CI builder
#     reuses the module cache. Source edits re-download nothing.
#   * GOCACHE stays a cache mount: compile cache is builder-local (mounts are
#     NOT exported) and cheap to rebuild — Go compiles fast enough that this
#     only affects local incremental rebuilds.
#   * CGO_ENABLED=0 -> static binary; prod stage is literally `scratch`.

# Pinned (supply-chain hardening): bump tag+digest together via
# `docker buildx imagetools inspect golang:1-alpine`.
FROM golang:1-alpine@sha256:d200d2dd76b03a99b52651fd1325aff7dcd35422c35c01bac56571b0507f3deb AS base
WORKDIR /app
ENV CGO_ENABLED=0

# --- deps: module download INTO THE LAYER (the shared cache key) -----------------
FROM base AS deps
COPY go.mod go.sum* ./
RUN go mod download

# --- dev: bind-mount source (compose), go run -------------------------------------
FROM deps AS dev
COPY . .
# Hot reload (optional): uncomment to add Air, then CMD below:
# RUN --mount=type=cache,id=gobuild,target=/root/.cache/go-build \
#     go install github.com/air-verse/air@v1.52.3
EXPOSE 3000
CMD ["go", "run", "."]

# --- build: static binary -----------------------------------------------------------
FROM deps AS build
COPY . .
RUN --mount=type=cache,id=gobuild,target=/root/.cache/go-build \
    go build -trimpath -ldflags="-s -w" -o /out/app .

# --- prod: scratch + static binary, non-root ----------------------------------------
# NOTE: no HEALTHCHECK is possible in `scratch` — there is no shell, wget or
# curl inside. If you need one, add a tiny statically-built healthcheck helper
# binary, or let your orchestrator (compose healthcheck with a sidecar,
# Kubernetes probes) do the probing.
FROM scratch AS prod
COPY --from=build /out/app /app
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
USER 65534:65534
EXPOSE 3000
ENTRYPOINT ["/app"]
