defmodule SduiDemo.Application do
  use Application

  @impl true
  def start(_type, _args) do
    AshSDUI.Registry.init_table()
    SduiDemo.DemoData.bootstrap()

    SduiDemo.UI.Layouts.DashboardLayout.register()

    children = [
      {Phoenix.PubSub, name: SduiDemo.PubSub},
      SduiDemoWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: SduiDemo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    SduiDemoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
