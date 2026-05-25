FROM --platform=linux/amd64 elixir:latest AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl unzip \
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
RUN MIX_ENV=prod mix compile && \
    MIX_ENV=prod mix assets.deploy && \
    MIX_ENV=prod mix release server --overwrite

FROM --platform=linux/amd64 elixir:latest

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates openssl curl git \
    && rm -rf /var/lib/apt/lists/*

# Pre-install hex/rebar into /tmp/.mix so the foundry (non-root) user can use mix
# without needing a writable home directory.
ENV MIX_HOME=/tmp/.mix
RUN mix local.hex --force && mix local.rebar --force && chmod -R 755 /tmp/.mix

COPY --from=builder /build/_build/prod/rel/server ./

RUN groupadd -r foundry && useradd -r -g foundry foundry && \
    chown -R foundry:foundry /app

USER foundry
EXPOSE 4001

HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost:${PORT:-4001}/healthz || exit 1

CMD ["/app/bin/server", "start"]
