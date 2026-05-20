FROM elixir:latest AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git nodejs npm \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY mix.exs mix.lock ./
COPY apps/foundry/mix.exs apps/foundry/mix.exs
COPY apps/foundry_web/mix.exs apps/foundry_web/mix.exs

COPY apps/foundry_web/assets/package.json apps/foundry_web/assets/package-lock.json apps/foundry_web/assets/

RUN mix local.hex --force && \
    mix local.rebar --force && \
    MIX_ENV=prod mix deps.get --only prod && \
    cd apps/foundry_web/assets && npm ci

COPY . .
RUN MIX_ENV=prod mix compile && \
    MIX_ENV=prod mix assets.deploy && \
    MIX_ENV=prod mix release server --overwrite

FROM debian:12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates openssl curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/_build/prod/rel/server ./

RUN groupadd -r foundry && useradd -r -g foundry foundry && \
    chown -R foundry:foundry /app

USER foundry
EXPOSE 4001

HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost:4001/health || exit 1

CMD ["/app/bin/server", "start"]
