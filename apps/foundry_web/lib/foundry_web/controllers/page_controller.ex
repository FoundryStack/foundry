defmodule FoundryWeb.PageController do
  use FoundryWeb, :controller
  alias Foundry.ProjectManager

  def preview_launch(conn, params) do
    # Don't start the preview while ProjectManager is still compiling dependencies —
    # mix holds the build lock during compile, so a concurrent mix phx.server would
    # block on the lock and produce no output, triggering a false timeout.
    project_manager_ready? = ProjectManager.get_status().state == :ready

    if project_manager_ready? do
      case Foundry.PreviewServer.get_status() do
        {:ok, %{state: :idle}} ->
          Foundry.PreviewServer.start_preview(preview_project_root())

        _ ->
          :ok
      end
    end

    render(conn, :preview_launch, target_url: preview_target_url(params))
  end

  def preview_status(conn, _params) do
    pm_status = ProjectManager.get_status()

    # If the project manager just became ready and nothing is running yet, kick off the preview.
    # This handles the case where the user loaded /preview-launch while the project was still
    # compiling — the page polls this endpoint and we start the preview as soon as it's safe.
    if pm_status.state == :ready do
      case Foundry.PreviewServer.get_status() do
        {:ok, %{state: :idle}} ->
          Foundry.PreviewServer.start_preview(preview_project_root())

        _ ->
          :ok
      end
    end

    status =
      case Foundry.PreviewServer.get_status() do
        {:ok, status} -> status
        {:error, _reason} -> %{state: :idle, output: "", last_error: "Preview server unavailable"}
      end

    # Merge project_manager_state so the browser can show "Compiling project…" while waiting.
    json(conn, Map.put(status, :project_manager_state, pm_status.state))
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
      can_open_local_dir: Foundry.RuntimeConfig.standalone?(),
      recent_projects: ProjectManager.recent_projects()
    )
  end

  def healthz(conn, _params) do
    json(conn, %{
      ok: true,
      mode: Foundry.RuntimeConfig.standalone?() && "standalone" || "local",
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

  defp preview_target_url(_params), do: Foundry.PreviewServer.preview_base_url(preview_project_root()) <> "/"

  defp preview_project_root do
    Foundry.ProjectManager.current_project_root()
  end

  defp validate_preview_target(target) do
    # Accept a server-relative path (no traversal) or a full URL on an allowed host.
    if String.starts_with?(target, "/") and not String.contains?(target, "..") do
      {:ok, normalize_route(target)}
    else
      with %URI{} = uri <- URI.parse(target),
           true <- preview_host?(uri.host),
           true <- is_integer(uri.port) or uri.scheme in ["http", "https"] do
        {:ok, URI.to_string(%{uri | query: nil, fragment: nil, path: normalize_route(uri.path)})}
      else
        _ -> :error
      end
    end
  end

  defp validate_preview_base(base) do
    with %URI{} = uri <- URI.parse(base),
         true <- preview_host?(uri.host) do
      uri
    else
      _ -> :error
    end
  end

  defp preview_host?(host) do
    allowed = ["localhost", "127.0.0.1"]
    preview_host = if Foundry.RuntimeConfig.standalone?(), do: nil, else: Foundry.RuntimeConfig.preview_host()
    host in allowed or (preview_host != nil and host == preview_host)
  end

  defp normalize_route("/" <> _ = route), do: route
  defp normalize_route(route) when is_binary(route), do: "/" <> route
  defp normalize_route(_route), do: "/"
end
