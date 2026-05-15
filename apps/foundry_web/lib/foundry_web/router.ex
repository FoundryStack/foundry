defmodule FoundryWeb.Router do
  use FoundryWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FoundryWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :mcp do
    plug :accepts, ["json"]
    plug :mcp_auth
  end

  defp mcp_auth(conn, _opts) do
    case System.get_env("FOUNDRY_MCP_API_KEY") do
      nil ->
        # No key configured — allow all requests (dev mode only)
        conn

      expected_key ->
        with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
             true <- token == expected_key do
          conn
        else
          _ ->
            conn
            |> put_resp_header("www-authenticate", "Bearer")
            |> send_resp(401, Jason.encode!(%{error: "Unauthorized"}))
            |> halt()
        end
    end
  end

  live_session :default, on_mount: [Foundry.TestScenario.LiveViewHook] do
    scope "/", FoundryWeb do
      pipe_through :browser

      live "/", SystemMapLive
    end
  end

  scope "/", FoundryWeb do
    pipe_through :browser

    get "/healthz", PageController, :healthz
    get "/project-manager", PageController, :project_manager
    get "/project-onboarding", PageController, :project_onboarding
    get "/project-launch", PageController, :project_launch_redirect
    get "/project-status", PageController, :project_status
    get "/project-recent", PageController, :recent_projects
    get "/preview-launch", PageController, :preview_launch
    get "/preview-status", PageController, :preview_status
  end

  # MCP server — exposes Foundry.Context tools to external agents
  # (Claude Code, Cursor, Codex CLI, etc.)
  scope "/foundry/mcp" do
    pipe_through :mcp

    forward "/", AshAi.Mcp.Router,
      tools: [
        :project_status,
        :module_context,
        :system_graph,
        :submit_proposal,
        :proposal_status,
        :run_lint,
        :read_doc
      ],
      protocol_version_statement: "2024-11-05",
      otp_app: :foundry
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:foundry_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FoundryWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
