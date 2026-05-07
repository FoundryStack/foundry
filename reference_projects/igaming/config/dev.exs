import Config

config :igaming_ref, IgamingRef.Web.Endpoint,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT", "4001"))],
  secret_key_base: "igaming-ref-preview-secret-key-base",
  server: true,
  check_origin: false,
  live_view: [signing_salt: "preview-live-view-salt"],
  pubsub_server: IgamingRef.PubSub
