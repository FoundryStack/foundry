import Config

# Disable Swoosh HTTP client — not needed for Foundry lint/context tasks
config :swoosh, :api_client, false

# Enable Ash tracing for scenario tests
config :ash, :tracer, [Foundry.TestScenario.AshTracer]

test_db_user =
  System.get_env("PGUSER") ||
    System.get_env("USER") ||
    "postgres"

config :igaming_ref, :foundry_tasks_only, false
config :igaming_ref, :token_signing_secret, "igaming-ref-test-token-signing-secret"

config :igaming_ref, IgamingRef.Repo,
  url:
    System.get_env(
      "ECTO_DATABASE_URL",
      "ecto://#{test_db_user}@localhost/igaming_ref_test"
    ),
  pool: Ecto.Adapters.SQL.Sandbox

config :igaming_ref, Oban,
  repo: IgamingRef.Repo,
  queues: false,
  plugins: false,
  testing: :manual

config :igaming_ref, IgamingRef.Web.Endpoint,
  secret_key_base: "igaming-ref-test-secret-key-base-that-is-long-enough-for-64-bytes",
  server: false,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: 4002],
  live_view: [signing_salt: "test-live-view-salt"],
  pubsub_server: IgamingRef.PubSub,
  render_errors: [view: IgamingRef.Web.ErrorView, accepts: [:html, :json]]
