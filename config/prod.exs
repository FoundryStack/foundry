import Config

config :foundry_web, FoundryWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

config :swoosh, :api_client, Swoosh.ApiClient.Req
config :swoosh, local: false
config :logger, level: :info
