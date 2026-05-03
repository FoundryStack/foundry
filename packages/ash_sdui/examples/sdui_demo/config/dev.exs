import Config

config :sdui_demo, SduiDemoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4001],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "sdui_demo_dev_secret_key_base_must_be_at_least_64_bytes_long_123456"

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
