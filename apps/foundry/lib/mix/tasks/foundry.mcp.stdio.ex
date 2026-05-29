defmodule Mix.Tasks.Foundry.Mcp.Stdio do
  use Mix.Task

  require Logger

  @shortdoc "MCP stdio bridge — proxies JSON-RPC to Foundry HTTP MCP endpoint"

  @moduledoc """
  Foundry MCP stdio bridge for Codex and other CLI tools.

  Usage:
    codex mcp add foundry --env BEARER_TOKEN=xxx -- mix foundry.mcp.stdio

  This task reads JSON-RPC MCP requests from stdin and forwards them to
  the local Foundry HTTP MCP endpoint (default: localhost:4000).
  """

  def run(_args) do
    # Suppress all output except JSON-RPC messages
    _ = :logger.set_module_level(Logger, :error)

    # :httpc requires :http_util which is lazily-loaded in OTP 28.
    # Explicitly load it now so it's available when :httpc makes its first request.
    _ = :inets.start()
    _ = :ssl.start()
    :code.load_file(:http_util)

    token = System.get_env("BEARER_TOKEN") || raise "BEARER_TOKEN env var required"
    host = System.get_env("FOUNDRY_MCP_HOST", "localhost")
    port = System.get_env("FOUNDRY_MCP_PORT", "4000")
    url = "http://#{host}:#{port}/foundry/mcp/"

    loop(url, token, nil)
  end

  defp loop(url, token, client_id) do
    case IO.read(:line) do
      :eof ->
        :ok

      line ->
        case process_request(line, url, token, client_id) do
          {:ok, new_client_id} -> loop(url, token, new_client_id)
          :error -> loop(url, token, client_id)
        end
    end
  end

  defp process_request(line, url, token, client_id) do
    try do
      request = Jason.decode!(String.trim(line))

      # Handle initialize specially
      if request["method"] == "initialize" do
        response = %{
          "jsonrpc" => "2.0",
          "id" => request["id"],
          "result" => %{
            "protocolVersion" => "2024-11-05",
            "capabilities" => %{
              "tools" => %{},
              "resources" => %{}
            },
            "serverInfo" => %{
              "name" => "Foundry MCP Server",
              "version" => "1.0.0"
            }
          }
        }

        IO.write(Jason.encode!(response) <> "\n")

        # Extract client_id from initialize request
        new_client_id = request["params"]["clientInfo"]["name"]
        {:ok, new_client_id}
      else
        # Forward all other requests to HTTP endpoint using :httpc (built-in OTP)
        body = Jason.encode!(request)
        auth_header = {~c"Authorization", String.to_charlist("Bearer #{token}")}

        result =
          :httpc.request(
            :post,
            {String.to_charlist(url), [auth_header], ~c"application/json",
             String.to_charlist(body)},
            [],
            body_format: :binary
          )

        response =
          case result do
            {:ok, {{_, 200, _}, _headers, resp_body}} ->
              Jason.decode!(resp_body)

            {:ok, {{_, status, _}, _headers, resp_body}} ->
              %{"error" => %{"code" => status, "message" => to_string(resp_body)}}

            {:error, reason} ->
              %{"error" => %{"code" => -32603, "message" => inspect(reason)}}
          end

        IO.write(Jason.encode!(response) <> "\n")
        {:ok, client_id}
      end
    rescue
      e ->
        Logger.error("MCP stdio error: #{inspect(e)}")

        error_response = %{
          "jsonrpc" => "2.0",
          "error" => %{
            "code" => -32603,
            "message" => "Internal error: #{Exception.message(e)}"
          },
          "id" => nil
        }

        IO.write(Jason.encode!(error_response) <> "\n")
        :error
    end
  end
end
