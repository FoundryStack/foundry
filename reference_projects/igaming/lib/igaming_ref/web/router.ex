defmodule IgamingRef.Web.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {IgamingRef.Web.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  live_session :default, on_mount: [Foundry.TestScenario.LiveViewHook] do
    scope "/", IgamingRef.Web do
      pipe_through :browser

      live "/", HomeLive
      live "/games/:id", GameLive
      live "/auth", AuthLive
      live "/deposit", DepositLive
      live "/withdrawal", WithdrawalLive
    end
  end

  scope "/api", IgamingRef.Web do
    pipe_through :api
  end
end
