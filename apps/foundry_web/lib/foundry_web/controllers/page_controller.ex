defmodule FoundryWeb.PageController do
  use FoundryWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def preview_launch(conn, params) do
    render(conn, :preview_launch, target_url: preview_target_url(params))
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

  defp normalize_route("/" <> _ = route), do: route
  defp normalize_route(route) when is_binary(route), do: "/" <> route
  defp normalize_route(_route), do: "/"
end
