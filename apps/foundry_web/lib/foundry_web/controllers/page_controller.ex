defmodule FoundryWeb.PageController do
  use FoundryWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def preview_launch(conn, params) do
    Foundry.PreviewServer.start_preview(preview_project_root())
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

  defp preview_target_url(%{"base" => base, "route" => route}) do
    with %URI{scheme: "http", host: "localhost"} = uri <- URI.parse(base),
         true <- is_integer(uri.port),
         normalized_route <- normalize_route(route) do
      URI.to_string(%{uri | path: normalized_route, query: nil, fragment: nil})
    else
      _ -> "http://localhost:4001/"
    end
  end

  defp preview_target_url(_params), do: "http://localhost:4001/"

  defp preview_project_root do
    Application.get_env(
      :foundry_web,
      :igaming_project_root,
      Path.expand("../../../../reference_projects/igaming", __DIR__)
    )
  end

  defp normalize_route("/" <> _ = route), do: route
  defp normalize_route(route) when is_binary(route), do: "/" <> route
  defp normalize_route(_route), do: "/"
end
