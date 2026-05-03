import Config

config :sdui_demo, SduiDemoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,
  secret_key_base: "sdui_demo_test_secret_key_base_must_be_at_least_64_bytes_long_12345"
