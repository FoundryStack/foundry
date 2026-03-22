defmodule Foundry.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {DNSCluster, query: Application.get_env(:foundry, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Foundry.PubSub}
      # Start a worker by calling: Foundry.Worker.start_link(arg)
      # {Foundry.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Foundry.Supervisor)
  end
end
