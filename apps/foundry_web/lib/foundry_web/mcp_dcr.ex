defmodule FoundryWeb.McpDcrController do
  use FoundryWeb, :controller

  require Logger

  def register(conn, _params) do
    body = conn.body_params

    with client_name when is_binary(client_name) <- body["client_name"],
         token <- generate_token(client_name) do
      # Store token with expiration (3600 seconds = 1 hour)
      expire_at = System.system_time(:second) + 3600
      FoundryWeb.McpTokenStore.store_token(token, expire_at)

      response = %{
        "client_id" => client_name,
        "client_secret" => nil,
        "access_token" => token,
        "token_type" => "Bearer",
        "expires_in" => 3600
      }

      conn
      |> put_status(:created)
      |> json(response)
    else
      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{"error" => "invalid_request", "error_description" => "client_name is required"})
    end
  end

  def well_known(conn, _params) do
    base = mcp_base_url(conn)

    config = %{
      "issuer" => base,
      "registration_endpoint" => base <> "/register",
      "token_endpoint" => base <> "/token",
      "authorization_endpoint" => base <> "/authorize"
    }

    json(conn, config)
  end

  def valid_token?(token) do
    FoundryWeb.McpTokenStore.valid_token?(token)
  end

  defp generate_token(client_name) do
    api_key = System.get_env("FOUNDRY_MCP_API_KEY", "dev-key")

    :crypto.hash(:sha256, api_key <> client_name <> timestamp())
    |> Base.encode16(case: :lower)
  end

  defp timestamp do
    System.system_time(:second) |> Integer.to_string()
  end

  defp mcp_base_url(conn) do
    host = conn.host
    scheme = case Plug.Conn.get_req_header(conn, "x-forwarded-proto") do
      [proto] -> proto
      [] -> "http"
    end
    port = case Plug.Conn.get_req_header(conn, "x-forwarded-port") do
      [p] -> String.to_integer(p)
      [] -> conn.port
    end

    base = case {scheme, port} do
      {"http", 80} -> "http://#{host}"
      {"https", 443} -> "https://#{host}"
      _ -> "#{scheme}://#{host}:#{port}"
    end

    base <> "/foundry/mcp"
  end
end
