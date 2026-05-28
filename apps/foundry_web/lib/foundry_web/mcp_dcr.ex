defmodule FoundryWeb.McpDcrController do
  use FoundryWeb, :controller

  require Logger

  @doc """
  Handle DCR registration request.

  Clients POST to /foundry/mcp/register with:
  {
    "client_name": "Claude Code",
    "client_uri": "https://claude.ai",
    "contacts": ["support@anthropic.com"]
  }

  Returns:
  {
    "client_id": "...",
    "client_secret": "...",
    "access_token": "...",
    "token_type": "Bearer",
    "expires_in": 3600
  }
  """
  def register(conn, _params) do
    body = conn.body_params

    with client_name when is_binary(client_name) <- body["client_name"],
         token <- generate_token(client_name) do
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
    config = %{
      "issuer" => mcp_server_url(),
      "registration_endpoint" => mcp_server_url() <> "/register",
      "token_endpoint" => mcp_server_url() <> "/token",
      "authorization_endpoint" => mcp_server_url() <> "/authorize"
    }

    json(conn, config)
  end

  defp generate_token(client_name) do
    # Use a deterministic token based on the API key and client name
    # In production, use a proper token generator with expiration
    api_key = System.get_env("FOUNDRY_MCP_API_KEY", "dev-key")

    :crypto.hash(:sha256, api_key <> client_name <> timestamp())
    |> Base.encode16(case: :lower)
  end

  defp timestamp do
    System.system_time(:second) |> Integer.to_string()
  end

  defp mcp_server_url do
    Foundry.Studio.mcp_server_url()
  end
end
