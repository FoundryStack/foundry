defmodule IgamingRef.Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :igaming_ref

  @doc false
  def config_change(changed, _new, removed) do
    if changed[:http] || is_nil(changed) do
      {:ok, _} = Supervisor.terminate_child(IgamingRef.Supervisor, __MODULE__)
      {:ok, _} = Supervisor.restart_child(IgamingRef.Supervisor, __MODULE__)
    end
    {:ok}
  end

  @session_options [
    store: :cookie,
    key: "_igaming_ref_key",
    signing_salt: "preview-signing-salt",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/assets",
    from: {:phoenix, "priv/static"},
    gzip: false

  plug Plug.Static,
    at: "/assets",
    from: {:phoenix_live_view, "priv/static"},
    gzip: false

  plug Plug.Static,
    at: "/",
    from: :igaming_ref,
    gzip: false,
    only: ~w(favicon.ico robots.txt)

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug IgamingRef.Web.Router
end
