defmodule FoundryWeb.WellKnownController do
  use FoundryWeb, :controller

  def mcp_discovery(conn, _params) do
    # Construct base URL from request or environment
    host = conn.host
    port = get_port(conn) || 4000
    scheme = get_scheme(conn)

    base_url =
      case {scheme, port} do
        {"http", 80} -> "http://#{host}"
        {"https", 443} -> "https://#{host}"
        _ -> "#{scheme}://#{host}:#{port}"
      end

    discovery = %{
      "mcpServers" => %{
        "foundry" => %{
          "url" => "#{base_url}/foundry/mcp/",
          "auth" => %{
            "type" => "oauth2",
            "registrationEndpoint" => "#{base_url}/foundry/mcp/register",
            "wellKnownEndpoint" => "#{base_url}/foundry/mcp/.well-known/oauth2-configuration"
          }
        }
      }
    }

    json(conn, discovery)
  end

  defp get_scheme(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-proto") do
      [proto] -> proto
      [] -> if conn.adapter |> elem(0) == :ssl, do: "https", else: "http"
    end
  end

  defp get_port(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-port") do
      [port] ->
        try do
          String.to_integer(port)
        rescue
          _ -> nil
        end

      [] ->
        # Try to get from environment, fallback to nil (caller will use 4000)
        System.get_env("PORT")
        |> case do
          nil -> nil
          port_str ->
            try do
              String.to_integer(port_str)
            rescue
              _ -> nil
            end
        end
    end
  end
end
