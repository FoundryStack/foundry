defmodule Foundry.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize Mnesia schema and tables before starting the supervisor
    init_mnesia()

    children = [
      {DNSCluster, query: Application.get_env(:foundry, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Foundry.PubSub},
      Foundry.Context.ScenarioCache
      # Start a worker by calling: Foundry.Worker.start_link(arg)
      # {Foundry.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Foundry.Supervisor)
  end

  # ---------------------------------------------------------------------------
  # Mnesia initialization
  # ---------------------------------------------------------------------------

  defp init_mnesia do
    # Create and start Mnesia on the local node
    :mnesia.create_schema([node()])
    :mnesia.start()

    # Determine table type based on node configuration
    table_config =
      if node() == :nonode@nohost do
        [ram_copies: [node()]]
      else
        [disc_copies: [node()]]
      end

    # Create the chat sessions table if it doesn't exist
    # Ash.DataLayer.Mnesia stores each resource as `{_pkey, val}`.
    case :mnesia.create_table(
           :foundry_chat_sessions,
           Keyword.merge(
             [attributes: [:_pkey, :val]],
             table_config
           )
         ) do
      {:aborted, {:already_exists, _}} ->
        :ok

      {:atomic, :ok} ->
        :ok

      error ->
        require Logger
        Logger.warning("Failed to create Mnesia table: #{inspect(error)}")
    end
  end
end
