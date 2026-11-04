# syntax=docker/dockerfile:1
# Generic multi-stage Dockerfile template for wsl2-docker-cache-kit.
#
# This file BUILDS as-is (placeholder steps) so you can test the cache loop
# immediately with templates/build.sh. Replace the marked sections with your
# real commands, keeping the ORDER: manifest/lockfile -> install -> source -> build.
#
# Why this order matters: the first changed instruction invalidates everything
# after it. Lockfile-first ordering means source edits never re-install deps.
# See docs/cache-guide.md.

# --- Stage 1: dependencies ----------------------------------------------------
FROM alpine:3.20 AS deps
WORKDIR /src

# TODO(your-stack): COPY ONLY your lockfile/manifests here, e.g.:
#   COPY package.json pnpm-lock.yaml ./
#   COPY requirements.txt ./
#   COPY go.mod go.sum ./
# README.md below is just a stand-in so this template builds out of the box
# (nearly every project has one) - replace it with your lockfile COPY.
COPY README.md ./

# TODO(your-stack): replace with your dependency install command.
# The cache mount keeps the package manager's cache dir across builds on this
# builder without baking it into the image layer:
#   RUN --mount=type=cache,target=/root/.cache pip install -r requirements.txt
#   RUN --mount=type=cache,target=/root/.local/share/pnpm pnpm install --frozen-lockfile
RUN --mount=type=cache,target=/tmp/kit-cache \
    echo "placeholder: install dependencies" > deps.done

# --- Stage 2: build -----------------------------------------------------------
FROM deps AS build
WORKDIR /src

# TODO(your-stack): keep this COPY (source on top of deps), it's the point.
COPY . .

# TODO(your-stack): replace with your compile/build command, e.g. `pnpm build`.
RUN --mount=type=cache,target=/tmp/kit-cache \
    echo "placeholder: compile" > build.done

# --- Stage 3: final image (minimal runtime) ------------------------------------
FROM alpine:3.20 AS final
WORKDIR /app
# TODO(your-stack): copy only what runtime needs:
#   COPY --from=build /src/dist ./dist
COPY --from=build /src/build.done .
CMD ["cat", "build.done"]
