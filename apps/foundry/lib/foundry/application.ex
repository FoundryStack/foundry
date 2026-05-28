defmodule Foundry.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    # Load .env file to make FOUNDRY_MCP_API_KEY available to external tools (Codex, Claude Code)
    load_env_file(".env")

    case Foundry.Studio.parse_studio_argv(System.argv()) do
      {:ok, launch_opts} ->
        start_studio_mode(launch_opts)

      {:error, message} ->
        {:error, message}

      :no_command ->
        start_default_mode()
    end
  end

  defp load_env_file(path) do
    if File.exists?(path) do
      File.read!(path)
      |> String.split("\n")
      |> Enum.each(fn line ->
        case String.trim(line) do
          "" ->
            :ok

          "# " <> _comment ->
            :ok

          line ->
            case String.split(line, "=", parts: 2) do
              [key, value] ->
                System.put_env(String.trim(key), String.trim(value))

              _ ->
                :ok
            end
        end
      end)
    end
  rescue
    _ -> :ok
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

    :ok = Foundry.Studio.configure_runtime(project_root)

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
        Logger.error("Foundry Studio did not become healthy on port #{port}.")
        exit(:shutdown)

      {:error, reason} ->
        Logger.error("Failed to finalize Foundry Studio launch: #{inspect(reason)}")
        exit(:shutdown)
    end
  end

  defp init_mnesia do
    :mnesia.create_schema([node()])
    :mnesia.start()

    table_config =
      if node() == :nonode@nohost do
        [ram_copies: [node()]]
      else
        [disc_copies: [node()]]
      end

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
        Logger.warning("Failed to create Mnesia table: #{inspect(error)}")
    end
  end
end
