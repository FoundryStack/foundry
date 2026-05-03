defmodule SduiDemoWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :sdui_demo

  @session_options [
    store: :cookie,
    key: "_sdui_demo_key",
    signing_salt: "sdui_demo_salt"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :sdui_demo,
    gzip: not code_reloading?,
    only: SduiDemoWeb.static_paths()

  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug SduiDemoWeb.Router
end
