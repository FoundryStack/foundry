defmodule FoundryWeb.McpToolsHandler do
  @moduledoc """
  Custom MCP handler that properly serializes Simple resources.

  Intercepts tool/call requests before they reach AshAi, executes them,
  and returns properly serialized JSON data.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    # Check if this is a tool/call or tools/list request by inspecting params
    # Note: params are parsed by Plug.Parsers before this runs
    case {conn.method, conn.params} do
      {"POST", %{"method" => "tools/list"} = params} ->
        handle_tools_list(conn, params)

      {"POST", %{"method" => "tools/call"} = params} ->
        handle_tool_call(conn, params)

      _ ->
        # Pass through to AshAi
        conn
    end
  end

  defp handle_tools_list(conn, %{"id" => req_id}) do
    tools = FoundryWeb.McpToolDefinitions.tools()

    response = %{
      "jsonrpc" => "2.0",
      "id" => req_id,
      "result" => %{
        "tools" => tools
      }
    }

    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(200, Jason.encode!(response))
    |> halt()
  end

  defp handle_tools_list(conn, _params) do
    conn
  end

  defp handle_tool_call(conn, %{"id" => req_id, "params" => params}) do
    tool_name = params["name"]
    arguments = params["arguments"] || %{}
    project_root = FoundryWeb.ChatConfig.project_root()

    try do
      case execute_tool(tool_name, Map.put(arguments, "project_root", project_root)) do
        {:ok, data} ->
          response = %{
            "jsonrpc" => "2.0",
            "id" => req_id,
            "result" => %{
              "isError" => false,
              "content" => [%{
                "type" => "text",
                "text" => Jason.encode!(data)
              }]
            }
          }

          conn
          |> put_resp_header("content-type", "application/json")
          |> send_resp(200, Jason.encode!(response))
          |> halt()

        {:error, reason} ->
          error_response = %{
            "jsonrpc" => "2.0",
            "id" => req_id,
            "error" => %{
              "code" => -32000,
              "message" => to_string(reason)
            }
          }

          conn
          |> put_resp_header("content-type", "application/json")
          |> send_resp(200, Jason.encode!(error_response))
          |> halt()
      end
    rescue
      e ->
        error_response = %{
          "jsonrpc" => "2.0",
          "id" => req_id,
          "error" => %{
            "code" => -32000,
            "message" => Exception.message(e)
          }
        }

        conn
        |> put_resp_header("content-type", "application/json")
        |> send_resp(200, Jason.encode!(error_response))
        |> halt()
    end
  end

  defp handle_tool_call(conn, _params) do
    conn
  end

  defp execute_tool(tool_name, args) do
    case tool_name do
      "project_status" -> Foundry.MCP.Tools.project_status(args)
      "module_context" -> Foundry.MCP.Tools.module_context(args)
      "system_graph" -> Foundry.MCP.Tools.system_graph(args)
      "run_lint" -> Foundry.MCP.Tools.run_lint(args)
      "read_doc" -> Foundry.MCP.Tools.read_doc(args)
      _ -> {:error, "Unknown tool: #{tool_name}"}
    end
  end
end
