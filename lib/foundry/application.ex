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
      {Foundry.PreviewServer, []},
      {Foundry.ProjectManager, []}
      # Start a worker by calling: Foundry.Worker.start_link(arg)
      # {Foundry.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Foundry.Supervisor)
  end

  defp start_studio_mode(launch_opts) do
    init_mnesia()

    # In standalone mode, the port was already selected by runtime.exs before
    # the endpoint started. Read it from the endpoint config instead of
    # re-selecting via prepare_launch, which would diverge from the running endpoint.
    port = get_in(
      Application.get_env(:foundry_web, FoundryWeb.Endpoint, []),
      [:http, :port]
    ) || 4000

    project_root = Keyword.get(launch_opts, :project_root, File.cwd!()) |> Path.expand()
    open_browser? = Keyword.get(launch_opts, :open_browser?, true)
    url = Foundry.Studio.url_for_port(port)

    :ok = Foundry.Studio.configure_runtime(project_root, port)

    launch = %{
      open_browser?: open_browser?,
      port: port,
      project_root: project_root,
      reused?: false,
      url: url
    }

    children = [
      {DNSCluster, query: Application.get_env(:foundry, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Foundry.PubSub},
      Foundry.Context.ScenarioCache,
      {Foundry.PreviewServer, []},
      {Foundry.ProjectManager, []},
      {Task, fn -> finalize_studio_launch(launch) end}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Foundry.Supervisor)
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
