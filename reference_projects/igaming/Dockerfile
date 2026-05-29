ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=26.0.1
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-bookworm-20260518-slim"
ARG RUNNER_IMAGE="debian:bookworm-slim"
ARG PREVIEW_RUNTIME_EXS_B64=""
ARG PREVIEW_ENTRYPOINT_B64=""
ARG PREVIEW_MIGRATE_B64=""

FROM ${BUILDER_IMAGE} AS builder

WORKDIR /app
ENV MIX_ENV=prod

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git gcc g++ make curl && \
    rm -rf /var/lib/apt/lists/*

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config ./config
RUN mix deps.get --only $MIX_ENV && \
    mix deps.compile

COPY . .

ARG PREVIEW_RUNTIME_EXS_B64
RUN if [ -n "$PREVIEW_RUNTIME_EXS_B64" ]; then mkdir -p config && echo "$PREVIEW_RUNTIME_EXS_B64" | base64 -d > config/runtime.exs; fi

RUN if [ -f "assets/package.json" ]; then \
    apt-get update && apt-get install -y --no-install-recommends nodejs npm && \
    cd assets && npm ci && npm run build && cd .. && \
    rm -rf /var/lib/apt/lists/*; \
fi

RUN mix compile && \
    mix release

FROM ${RUNNER_IMAGE} AS runner

ARG PREVIEW_RUNTIME_EXS_B64
ARG PREVIEW_ENTRYPOINT_B64
ARG PREVIEW_MIGRATE_B64

ENV LANG=C.UTF-8 LANGUAGE=C.UTF-8 LC_ALL=C.UTF-8 ELIXIR_ERL_OPTIONS="+fnu"
ENV PHX_SERVER=true

RUN apt-get update && apt-get install -y --no-install-recommends \
    libstdc++6 openssl ca-certificates bash curl git postgresql-client && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/_build/prod/rel/igaming_ref /app/igaming_ref/

RUN mkdir -p /app/bin

RUN if [ -n "$PREVIEW_RUNTIME_EXS_B64" ]; then \
    mkdir -p /app/igaming_ref/etc && \
    echo "$PREVIEW_RUNTIME_EXS_B64" | base64 -d > /app/igaming_ref/etc/runtime.exs && \
    echo "DEBUG: Wrote runtime.exs to /app/igaming_ref/etc/runtime.exs ($(wc -c < /app/igaming_ref/etc/runtime.exs) bytes)"; \
  fi

RUN if [ -n "$PREVIEW_ENTRYPOINT_B64" ]; then \
    echo "$PREVIEW_ENTRYPOINT_B64" | base64 -d > /app/bin/entrypoint.sh && chmod +x /app/bin/entrypoint.sh; \
    else \
    printf '#!/bin/sh\nset -e\nAPP_NAME="igaming_ref"\nRELEASE_BIN="/app/bin/${APP_NAME}"\nif [ ! -x "$RELEASE_BIN" ]; then echo "Release executable not found: $RELEASE_BIN" >&2; exit 1; fi\nexec "$RELEASE_BIN" start\n' > /app/bin/entrypoint.sh && chmod +x /app/bin/entrypoint.sh; \
    fi

RUN if [ -n "$PREVIEW_MIGRATE_B64" ]; then \
    echo "$PREVIEW_MIGRATE_B64" | base64 -d > /app/bin/migrate.exs; \
    fi

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 CMD curl -sf http://localhost:4000/health || exit 1

EXPOSE 4000
ENTRYPOINT ["/app/bin/entrypoint.sh"]
