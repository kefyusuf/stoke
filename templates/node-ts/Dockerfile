# syntax=docker/dockerfile:1
# Node.js/TypeScript template for stoke — prod + dev targets.
#
# Cache design (docs/cache-guide.md):
#   * lockfile-first COPY  -> the deps layer is the cache key; source edits never
#                             re-install dependencies (locally or in CI).
#   * pnpm store lives in a cache mount -> fast re-installs, slim image layers.
#
# Build:
#   docker buildx build --target prod -t myapp:prod .
#   docker buildx build --target dev  -t myapp:dev .
# Or via the kit's cache wrapper (shared local<->CI cache):
#   CACHE_REF=127.0.0.1:5000/myapp:buildcache DOCKERFILE=Dockerfile ../build.sh

# Pinned (supply-chain hardening): bump tag+digest together via
# `docker buildx imagetools inspect node:22-alpine`.
FROM node:22-alpine@sha256:fe4f6d74e20370acb04ad889077d14d0f64a9c8ea6a42bc60cddf1e844699914 AS base
ENV PNPM_HOME=/pnpm
ENV PATH="/pnpm:$PATH"
# Keep in sync with package.json "packageManager".
RUN corepack enable && corepack prepare pnpm@9.15.0 --activate
WORKDIR /app

# --- deps: lockfile-first = the shared cache key -------------------------------
FROM base AS deps
COPY package.json pnpm-lock.yaml ./
RUN --mount=type=cache,id=pnpm,target=/pnpm/store \
    pnpm install --frozen-lockfile

# --- dev: hot-reload server; source usually comes from a bind mount ------------
FROM deps AS dev
ENV NODE_ENV=development
COPY . .
EXPOSE 3000
CMD ["pnpm", "dev"]

# --- build: compile TypeScript -> dist/ -----------------------------------------
FROM deps AS build
COPY . .
RUN --mount=type=cache,id=tsc,target=/app/node_modules/.cache \
    pnpm build

# --- prod: prod-only deps + compiled output, non-root ---------------------------
FROM base AS prod
ENV NODE_ENV=production
COPY package.json pnpm-lock.yaml ./
RUN --mount=type=cache,id=pnpm,target=/pnpm/store \
    pnpm install --frozen-lockfile --prod
COPY --from=build /app/dist ./dist
USER node
EXPOSE 3000
CMD ["pnpm", "start"]
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${PORT:-3000}/" >/dev/null 2>&1 || exit 1
