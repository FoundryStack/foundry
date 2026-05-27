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

FROM --platform=linux/amd64 elixir:1.19-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates openssl curl git build-essential gosu \
    && rm -rf /var/lib/apt/lists/*

# Pre-install hex/rebar into /tmp/.mix so the foundry (non-root) user can use mix
# without needing a writable home directory.
ENV MIX_HOME=/tmp/.mix
RUN mix local.hex --force && mix local.rebar --force && chmod -R 755 /tmp/.mix

COPY --from=builder /build/_build/prod/rel/server ./

RUN groupadd -g 1000 deploy && useradd -u 1000 -g deploy deploy && \
    mkdir -p /app/projects /home/deploy && \
    chown -R deploy:deploy /app /home/deploy

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 4000

HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost:${PORT:-4000}/healthz || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/app/bin/server", "start"]
