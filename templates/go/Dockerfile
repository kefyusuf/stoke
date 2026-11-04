# syntax=docker/dockerfile:1
# Go template for wsl2-docker-cache-kit — prod + dev targets.
#
# Cache design (docs/cache-guide.md):
#   * go mod download with a GOMODCACHE cache mount -> modules never re-download.
#   * GOCACHE cache mount -> incremental compilation across builds, locally and
#     in CI (shared registry cache, mode=max).
#   * CGO_ENABLED=0 -> static binary; prod stage is literally `scratch`.
ARG GO_VERSION=1

FROM golang:${GO_VERSION}-alpine AS base
WORKDIR /app
ENV CGO_ENABLED=0

# --- deps: module download (the shared cache key) --------------------------------
FROM base AS deps
COPY go.mod go.sum* ./
RUN --mount=type=cache,id=gomod,target=/go/pkg/mod \
    go mod download

# --- dev: bind-mount source (compose), go run -------------------------------------
FROM deps AS dev
COPY . .
# Hot reload (optional): uncomment to add Air, then CMD below:
# RUN --mount=type=cache,id=gobuild,target=/root/.cache/go-build \
#     --mount=type=cache,id=gomod,target=/go/pkg/mod \
#     go install github.com/air-verse/air@v1.52.3
EXPOSE 3000
CMD ["go", "run", "."]

# --- build: static binary -----------------------------------------------------------
FROM deps AS build
COPY . .
RUN --mount=type=cache,id=gobuild,target=/root/.cache/go-build \
    --mount=type=cache,id=gomod,target=/go/pkg/mod \
    go build -trimpath -ldflags="-s -w" -o /out/app .

# --- prod: scratch + static binary, non-root ----------------------------------------
FROM scratch AS prod
COPY --from=build /out/app /app
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
USER 65534:65534
EXPOSE 3000
ENTRYPOINT ["/app"]
