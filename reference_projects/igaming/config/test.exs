import Config

# Disable Swoosh HTTP client — not needed for Foundry lint/context tasks
config :swoosh, :api_client, false

test_db_user =
  System.get_env("PGUSER") ||
    System.get_env("USER") ||
    "postgres"

config :igaming_ref, :foundry_tasks_only, false

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
