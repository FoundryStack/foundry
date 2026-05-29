import Config

# Enable debug logging to catch LiveView and form submission issues
config :logger, level: :debug

bind_ip =
  case System.get_env("PHX_BIND_IP", "127.0.0.1") |> String.split(".") do
    [a, b, c, d] -> {String.to_integer(a), String.to_integer(b), String.to_integer(c), String.to_integer(d)}
    _ -> {127, 0, 0, 1}
  end

config :igaming_ref, IgamingRef.Web.Endpoint,
  url: [host: System.get_env("PHX_HOST", "localhost")],
  http: [ip: bind_ip, port: String.to_integer(System.get_env("PORT", "4001"))],
  secret_key_base: "igaming-ref-preview-secret-key-base-1234567890abcdefghijklmnopqr",
  server: true,
  check_origin: false,
  live_view: [signing_salt: "preview-live-view-salt"],
  pubsub_server: IgamingRef.PubSub,
  render_errors: [view: IgamingRef.Web.ErrorView, accepts: ~w(html json)]
