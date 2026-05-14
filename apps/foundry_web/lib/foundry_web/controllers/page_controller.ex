defmodule FoundryWeb.PageController do
  use FoundryWeb, :controller
  alias Foundry.ProjectManager

  def preview_launch(conn, params) do
    case Foundry.PreviewServer.get_status() do
      {:ok, %{state: state}} when state not in [:starting, :running] ->
        Foundry.PreviewServer.start_preview(preview_project_root())

      _ ->
        :ok
    end

    render(conn, :preview_launch, target_url: preview_target_url(params))
  end

  def preview_status(conn, _params) do
    status =
      case Foundry.PreviewServer.get_status() do
        {:ok, status} -> status
        {:error, _reason} -> %{state: :idle, output: "", last_error: "Preview server unavailable"}
      end

    json(conn, status)
  end

  def project_launch(conn, params) do
    maybe_start_project_action(params)
    render(conn, :project_launch, target_url: ~p"/")
  end

  def project_status(conn, _params) do
    json(conn, ProjectManager.get_status())
  end

  def healthz(conn, _params) do
    json(conn, %{
      ok: true,
      mode: if(System.get_env("FOUNDRY_STANDALONE", "0") == "1", do: "standalone", else: "local"),
      version: to_string(Application.spec(:foundry, :vsn) || "0.0.0")
    })
  end

  def redirect_to_home(conn, _params) do
    redirect(conn, to: ~p"/")
  end

  def recent_projects(conn, _params) do
    json(conn, %{recent_projects: ProjectManager.recent_projects()})
  end

  defp preview_target_url(%{"target" => target}) when is_binary(target) do
    case validate_preview_target(target) do
      {:ok, normalized_target} -> normalized_target
      :error -> preview_target_url(%{})
    end
  end

  defp preview_target_url(%{"base" => base, "route" => route}) do
    with %URI{} = base_uri <- validate_preview_base(base),
         normalized_route <- normalize_route(route) do
      URI.to_string(%{base_uri | path: normalized_route, query: nil, fragment: nil})
    else
      _ -> preview_target_url(%{})
    end
  end

  defp preview_target_url(_params), do: "http://localhost:4001/"

  defp preview_project_root do
    FoundryWeb.ChatConfig.project_root()
  end

  defp validate_preview_target(target) do
    with %URI{} = uri <- URI.parse(target),
         true <- preview_host?(uri.host),
         true <- is_integer(uri.port) do
      {:ok, URI.to_string(%{uri | query: nil, fragment: nil, path: normalize_route(uri.path)})}
    else
      _ -> :error
    end
  end

  defp validate_preview_base(base) do
    with %URI{} = uri <- URI.parse(base),
         true <- preview_host?(uri.host),
         true <- is_integer(uri.port) do
      uri
    else
      _ -> :error
    end
  end

  defp preview_host?(host), do: host in ["localhost", "127.0.0.1"]

  defp normalize_route("/" <> _ = route), do: route
  defp normalize_route(route) when is_binary(route), do: "/" <> route
  defp normalize_route(_route), do: "/"

  defp maybe_start_project_action(%{"repo_url" => repo_url, "parent_dir" => parent_dir})
       when repo_url != "" and parent_dir != "" do
    ProjectManager.clone_project(repo_url, parent_dir)
  end

  defp maybe_start_project_action(%{"path" => path}) when path != "" do
    ProjectManager.open_project(path)
  end

  defp maybe_start_project_action(_params), do: :ok
end
