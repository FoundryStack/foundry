defmodule SduiDemoWeb.Router do
  use SduiDemoWeb, :router
  import PhoenixStorybook.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SduiDemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/" do
    storybook_assets()
  end

  scope "/", SduiDemoWeb do
    pipe_through :browser

    live "/", Live.DemoLive

    live_storybook "/storybook", backend_module: SduiDemoWeb.Storybook
  end
end
