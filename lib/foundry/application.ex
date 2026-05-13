defmodule Foundry.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    case Foundry.Studio.parse_studio_argv(System.argv()) do
      {:ok, launch_opts} ->
        start_studio_mode(launch_opts)

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)

      :no_command ->
        start_default_mode()
    end
  end

  defp start_default_mode do
    # Initialize Mnesia schema and tables before starting the supervisor
    init_mnesia()

    children = [
      {DNSCluster, query: Application.get_env(:foundry, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Foundry.PubSub},
      Foundry.Context.ScenarioCache,
      {Foundry.PreviewServer, []}
      # Start a worker by calling: Foundry.Worker.start_link(arg)
      # {Foundry.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Foundry.Supervisor)
  end

  defp start_studio_mode(launch_opts) do
    init_mnesia()

    case Foundry.Studio.prepare_launch(launch_opts) do
      {:ok, %{reused?: true, url: url} = launch} ->
        Foundry.Studio.complete_reused_launch(launch)
        IO.puts("Foundry Studio already running at #{url}")
        System.halt(0)

      {:ok, launch} ->
        :ok = Foundry.Studio.configure_runtime(launch.project_root, launch.port)

        children = [
          {DNSCluster, query: Application.get_env(:foundry, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: Foundry.PubSub},
          Foundry.Context.ScenarioCache,
          {Foundry.PreviewServer, []},
          {Task, fn -> finalize_studio_launch(launch) end}
        ]

        Supervisor.start_link(children, strategy: :one_for_one, name: Foundry.Supervisor)

      {:error, {:port_unavailable, port}} ->
        IO.puts(:stderr, "Foundry Studio could not use port #{port}.")
        System.halt(1)

      {:error, reason} ->
        IO.puts(:stderr, "Failed to prepare Foundry Studio: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp finalize_studio_launch(launch) do
    case Foundry.Studio.finalize_launch(launch) do
      :ok ->
        :ok

      {:error, {:health_timeout, port}} ->
        IO.puts(:stderr, "Foundry Studio did not become healthy on port #{port}.")
        System.halt(1)

      {:error, reason} ->
        IO.puts(:stderr, "Failed to finalize Foundry Studio launch: #{inspect(reason)}")
        System.halt(1)
    end
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
