defmodule SduiDemoWeb.Router do
  use SduiDemoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SduiDemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", SduiDemoWeb do
    pipe_through :browser
    live "/", Live.DemoLive
  end
end
