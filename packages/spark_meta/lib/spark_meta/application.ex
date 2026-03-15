defmodule SparkMeta.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SparkMeta.Registry
    ]

    opts = [strategy: :one_for_one, name: SparkMeta.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    # Register Ash handler if Ash is loaded
    if Code.ensure_loaded?(Ash.Resource.Dsl) do
      SparkMeta.Registry.register(Ash.Resource.Dsl, SparkMeta.Handlers.AshResource)
    end

    {:ok, pid}
  end
end
