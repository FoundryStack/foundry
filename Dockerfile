FROM --platform=linux/amd64 elixir:1.19-slim AS builder

ARG GIT_SHA=unknown

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl unzip ca-certificates \
    && curl -fsSL https://bun.sh/install | bash \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/root/.bun/bin:$PATH"

WORKDIR /build

COPY mix.exs mix.lock ./
COPY apps/foundry/mix.exs apps/foundry/mix.exs
COPY apps/foundry_web/mix.exs apps/foundry_web/mix.exs

COPY apps/foundry_web/assets/package.json apps/foundry_web/assets/bun.lock apps/foundry_web/assets/

RUN mix local.hex --force && \
    mix local.rebar --force && \
    MIX_ENV=prod mix deps.get --only prod && \
    cd apps/foundry_web/assets && bun install --frozen-lockfile

COPY . .
# Cache-buster: include GIT_SHA in compile step to force rebuild on code changes
RUN echo "Building from $GIT_SHA" && \
    MIX_ENV=prod mix compile && \
    MIX_ENV=prod mix assets.deploy && \
    MIX_ENV=prod mix release server --overwrite && \
    rm -rf /build/deps /build/_build/prod/lib /root/.cache

# Pre-compile the igaming reference project so the preview server starts instantly
# without recompiling 100+ files. MIX_BUILD_PATH=_build/preview matches manifest.exs.
RUN cd /build/reference_projects/igaming && \
    MIX_HOME=/tmp/.mix MIX_ENV=dev MIX_BUILD_PATH=_build/preview mix deps.get && \
    MIX_HOME=/tmp/.mix MIX_ENV=dev MIX_BUILD_PATH=_build/preview mix compile

FROM --platform=linux/amd64 elixir:1.19-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates openssl curl git \
    && rm -rf /var/lib/apt/lists/*

# Pre-install hex/rebar into /tmp/.mix so the foundry (non-root) user can use mix
# without needing a writable home directory.
ENV MIX_HOME=/tmp/.mix
RUN mix local.hex --force && mix local.rebar --force && chmod -R 755 /tmp/.mix

COPY --from=builder /build/_build/prod/rel/server ./

# Copy the pre-compiled igaming reference project to the path baked into the release config.
# The compile-time path is /build/reference_projects/igaming (WORKDIR was /build during build).
# We copy deps too so mix can do fast incremental checks without downloading anything.
COPY --from=builder /build/reference_projects/igaming /build/reference_projects/igaming

RUN groupadd -g 1000 deploy && useradd -u 1000 -g deploy deploy && \
    chown -R deploy:deploy /app && \
    chown -R deploy:deploy /build/reference_projects

USER deploy
EXPOSE 4001

HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost:${PORT:-4001}/healthz || exit 1

CMD ["/app/bin/server", "start"]
