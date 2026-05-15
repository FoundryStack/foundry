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

  def project_onboarding(conn, %{"path" => path}) do
    normalized = path |> String.trim() |> Path.expand()

    case ProjectManager.classify_folder(normalized) do
      :existing_project ->
        redirect(conn, to: ~p"/?path=#{normalized}")

      :empty_folder ->
        deps = Foundry.DepChecker.check_all()

        render(conn, :project_onboarding,
          step: "check_deps",
          folder_path: normalized,
          project_name: Path.basename(normalized),
          deps: deps,
          blocking_missing: Foundry.DepChecker.blocking_missing?(deps)
        )

      :partial_project ->
        render(conn, :project_onboarding,
          step: "partial_confirm",
          folder_path: normalized,
          project_name: Path.basename(normalized),
          deps: %{},
          blocking_missing: false
        )

      {:error, _} ->
        conn |> put_flash(:error, "Directory not found.") |> redirect(to: ~p"/project-manager")
    end
  end

  def project_onboarding(conn, _params) do
    redirect(conn, to: ~p"/project-manager")
  end

  def project_launch_redirect(conn, params) do
    redirect(conn, to: "/?#{URI.encode_query(params)}")
  end

  def project_status(conn, _params) do
    json(conn, ProjectManager.get_status())
  end

  def project_manager(conn, _params) do
    render(conn, :project_manager,
      can_open_local_dir: System.get_env("FOUNDRY_STANDALONE", "0") == "1",
      recent_projects: ProjectManager.recent_projects()
    )
  end

  def healthz(conn, _params) do
    json(conn, %{
      ok: true,
      mode: System.get_env("FOUNDRY_STANDALONE", "0") == "1" && "standalone" || "local",
      version: to_string(Application.spec(:foundry, :vsn) || "0.0.0")
    })
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
end
