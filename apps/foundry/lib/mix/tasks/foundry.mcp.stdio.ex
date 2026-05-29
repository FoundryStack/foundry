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

    # :httpc is part of :inets. Use ensure_all_started to guarantee all
    # internal modules (including :http_util in OTP 28) are loaded before use.
    :application.ensure_all_started(:inets)
    :application.ensure_all_started(:ssl)

    token = System.get_env("BEARER_TOKEN") || raise "BEARER_TOKEN env var required"
    host = System.get_env("FOUNDRY_MCP_HOST", "localhost")

    # Treat an explicit port as the first discovery candidate. The bridge still
    # verifies it because Codex configs and ~/.foundry.port can outlive servers.
    explicit_port = System.get_env("FOUNDRY_MCP_PORT")

    loop(token, host, explicit_port, nil)
  end

  defp discover_foundry_port(host, explicit_port \\ nil) do
    home_dir = System.get_env("FOUNDRY_HOME") || System.user_home!()
    port_file = Path.join(home_dir, ".foundry.port")

    [explicit_port, read_port_file(port_file) | common_ports()]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
    |> Enum.find_value("4000", fn port ->
      if healthy_server?(host, port), do: port
    end)
  end

  defp read_port_file(port_file) do
    with {:ok, contents} <- File.read(port_file),
         {port, ""} when port > 0 <- Integer.parse(String.trim(contents)) do
      port
    else
      _ -> nil
    end
  end

  defp common_ports do
    Enum.to_list(4000..4010) ++ Enum.to_list(8000..8010)
  end

  defp healthy_server?(host, port) do
    url = "http://#{host}:#{port}/healthz"

    case :httpc.request(:get, {String.to_charlist(url), []}, [timeout: 200], body_format: :binary) do
      {:ok, {{_, 200, _}, _, _}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp loop(token, host, explicit_port, client_id) do
    port = discover_foundry_port(host, explicit_port)
    loop_with_port(token, host, port, client_id)
  end

  defp loop_with_port(token, host, port, client_id) do
    case IO.read(:line) do
      :eof ->
        :ok

      line ->
        url = "http://#{host}:#{port}/foundry/mcp/"

        case process_request(line, url, token, client_id) do
          {:ok, new_client_id} ->
            loop_with_port(token, host, port, new_client_id)

          :error ->
            # On error, try rediscovery (server may have restarted)
            new_port = discover_foundry_port(host)
            loop_with_port(token, host, new_port, client_id)
        end
    end
  end

  defp tools do
    [
      %{
        name: "project_status",
        description:
          "Get comprehensive status of the current Foundry project including domains, modules, lint errors, and stack versions",
        inputSchema: %{type: "object", properties: %{}}
      },
      %{
        name: "system_graph",
        description:
          "Retrieve the system architecture graph showing all modules, domains, pages, and their dependencies with visualization data",
        inputSchema: %{type: "object", properties: %{}}
      },
      %{
        name: "module_context",
        description:
          "Get detailed context for a specific module including its code, domain, type (controller/schema/service), and relationships",
        inputSchema: %{
          type: "object",
          properties: %{
            module_id: %{
              type: "string",
              description:
                "The module identifier (e.g., 'IgamingRef.Accounts.User'). If not provided, returns the first module."
            }
          }
        }
      },
      %{
        name: "run_lint",
        description:
          "Run Foundry linting to find architectural violations, unused code, and violations of project rules",
        inputSchema: %{type: "object", properties: %{}}
      },
      %{
        name: "read_doc",
        description:
          "Read a specification or architectural document from the project's .foundry/docs directory",
        inputSchema: %{
          type: "object",
          properties: %{
            id: %{
              type: "string",
              description:
                "The document identifier or path. If not provided, returns the first document."
            }
          }
        }
      },
      %{
        name: "submit_proposal",
        description:
          "Submit an architectural proposal (refactoring, new feature, or system change) for evaluation",
        inputSchema: %{
          type: "object",
          required: ["title", "description", "reasoning"],
          properties: %{
            title: %{type: "string", description: "Title of the proposal"},
            description: %{
              type: "string",
              description: "Detailed description of the proposed change"
            },
            reasoning: %{type: "string", description: "Architectural reasoning for this proposal"}
          }
        }
      },
      %{
        name: "proposal_status",
        description: "Check the status of a previously submitted proposal",
        inputSchema: %{
          type: "object",
          properties: %{
            proposal_id: %{type: "string", description: "The unique proposal identifier"}
          }
        }
      },
      %{
        name: "edit_file",
        description: "Edit or create a source file with complete code replacement",
        inputSchema: %{
          type: "object",
          required: ["path", "content"],
          properties: %{
            path: %{type: "string", description: "File path relative to project root"},
            content: %{type: "string", description: "The complete file content"}
          }
        }
      }
    ]
  end

  defp process_request(line, url, token, client_id) do
    try do
      request = Jason.decode!(String.trim(line))

      case request["method"] do
        "initialize" ->
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

          new_client_id = get_in(request, ["params", "clientInfo", "name"])
          {:ok, new_client_id}

        "notifications/initialized" ->
          # No response needed for notifications
          {:ok, client_id}

        "tools/list" ->
          # Handle locally — no HTTP server required for tool discovery
          response = %{
            "jsonrpc" => "2.0",
            "id" => request["id"],
            "result" => %{
              "tools" => tools()
            }
          }

          IO.write(Jason.encode!(response) <> "\n")
          {:ok, client_id}

        _ ->
          # Forward all other requests to HTTP endpoint using :httpc (built-in OTP)
          body = Jason.encode!(request)
          auth_header = {~c"Authorization", String.to_charlist("Bearer #{token}")}

          result =
            :httpc.request(
              :post,
              {String.to_charlist(url), [auth_header], ~c"application/json",
               String.to_charlist(body)},
              [timeout: 30_000],
              body_format: :binary
            )

          response =
            case result do
              {:ok, {{_, 200, _}, _headers, resp_body}} ->
                Jason.decode!(resp_body)

              {:ok, {{_, status, _}, _headers, resp_body}} ->
                %{
                  "jsonrpc" => "2.0",
                  "id" => request["id"],
                  "error" => %{"code" => status, "message" => to_string(resp_body)}
                }

              {:error, reason} ->
                %{
                  "jsonrpc" => "2.0",
                  "id" => request["id"],
                  "error" => %{"code" => -32603, "message" => inspect(reason)}
                }
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
