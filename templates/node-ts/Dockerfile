# syntax=docker/dockerfile:1
# Node.js/TypeScript template for wsl2-docker-cache-kit — prod + dev targets.
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
ARG NODE_VERSION=22

FROM node:${NODE_VERSION}-alpine AS base
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
