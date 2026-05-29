defmodule FoundryWeb.McpAuth do
  def generate_token(client_name) do
    api_key = System.get_env("FOUNDRY_MCP_API_KEY", "dev-key")
    :crypto.hash(:sha256, api_key <> client_name)
    |> Base.encode16(case: :lower)
  end
end
