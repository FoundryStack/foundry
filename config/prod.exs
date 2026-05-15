import Config

config :foundry_web, FoundryWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  check_origin: [
    "http://127.0.0.1:4000",
    "http://localhost:4000",
    "//127.0.0.1:4000",
    "//localhost:4000",
    "http://127.0.0.1",
    "http://localhost",
    "//127.0.0.1",
    "//localhost",
    "tauri://localhost",
    "tauri://localhost:4000"
  ]

config :swoosh, :api_client, Swoosh.ApiClient.Req
config :swoosh, local: false
config :logger, level: :info
