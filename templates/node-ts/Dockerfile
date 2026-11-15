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
# `docker buildx imagetools inspect node:26-alpine`.
FROM node:26-alpine@sha256:6bd9ab43c0ec0190ca7b2d193906cb8b7edf6e7f4afa43ddeccd6452710bffb5 AS base
ENV PNPM_HOME=/pnpm
ENV PATH="/pnpm:$PATH"
# Node >= 25 images no longer ship corepack - install pnpm via npm instead.
# Keep the version in sync with package.json "packageManager".
RUN npm install -g pnpm@9.15.0
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
