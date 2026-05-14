import Config

# Reduce log noise when running mix foundry.* (JSON output must be parseable)
config :logger, level: :warning

# Ash configuration
config :ash, :custom_types, money: AshMoney.Types.Money
config :ash, :known_types, [AshMoney.Types.Money]
config :igaming_ref, ash_domains: [
  IgamingRef.Accounts,
  IgamingRef.Finance,
  IgamingRef.Gaming,
  IgamingRef.Players,
  IgamingRef.Promotions,
  IgamingRef.Ops
]
config :igaming_ref, ecto_repos: [IgamingRef.Repo]

# ex_money / ex_cldr — required for Money types at runtime
config :ex_cldr, default_backend: IgamingRef.Cldr
config :ex_money, default_cldr_backend: IgamingRef.Cldr

# Database (required for Repo; use ECTO_DATABASE_URL or default)
config :igaming_ref, IgamingRef.Repo,
  url: System.get_env("ECTO_DATABASE_URL", "ecto://postgres:postgres@localhost/igaming_ref_dev")

# Oban (required for Application supervision)
config :igaming_ref, Oban,
  repo: IgamingRef.Repo,
  queues: [default: 10]

# When true, skip Repo/Oban (for mix foundry.* tasks without a running DB).
# Default true so Foundry tasks run without Postgres; set FOUNDRY_TASKS_ONLY=0 to start DB.
config :igaming_ref, :foundry_tasks_only, System.get_env("FOUNDRY_TASKS_ONLY", "1") != "0"

import_config "#{config_env()}.exs"
