defmodule FoundryWeb.McpToolsHandlerTest do
  use FoundryWeb.ConnCase

  @igaming_root Path.expand("../../../../../reference_projects/igaming", __DIR__)

  setup do
    Application.put_env(:foundry_web, :current_project_root, @igaming_root)
    token = FoundryWeb.McpAuth.generate_token("claude-code-foundry")
    {:ok, token: token}
  end

  defp mcp_post(conn, token, body) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> post("/foundry/mcp/", body)
  end

  defp parse_mcp_result(conn) do
    body = json_response(conn, 200)
    text = get_in(body, ["result", "content", Access.at(0), "text"])
    Jason.decode!(text)
  end

  describe "tools/list" do
    test "returns list of available tools", %{conn: conn, token: token} do
      body = %{"jsonrpc" => "2.0", "method" => "tools/list", "id" => 1, "params" => %{}}
      conn = mcp_post(conn, token, Jason.encode!(body))
      response = json_response(conn, 200)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      tool_names = response["result"]["tools"] |> Enum.map(& &1["name"])
      assert "project_status" in tool_names
      assert "system_graph" in tool_names
      assert "run_lint" in tool_names
      assert "read_doc" in tool_names
      assert "module_context" in tool_names
    end

    test "returns complete tool metadata including descriptions and input schemas", %{conn: conn, token: token} do
      body = %{"jsonrpc" => "2.0", "method" => "tools/list", "id" => 1, "params" => %{}}
      conn = mcp_post(conn, token, Jason.encode!(body))
      response = json_response(conn, 200)

      tools = response["result"]["tools"]
      assert is_list(tools)
      assert length(tools) > 0

      # Each tool must have name, description, and inputSchema
      Enum.each(tools, fn tool ->
        assert Map.has_key?(tool, "name"), "Tool missing 'name' field"
        assert Map.has_key?(tool, "description"), "Tool #{tool["name"]} missing 'description'"
        assert Map.has_key?(tool, "inputSchema"), "Tool #{tool["name"]} missing 'inputSchema'"
        assert is_binary(tool["description"]), "Description must be a string"
        assert is_map(tool["inputSchema"]), "inputSchema must be an object"
      end)

      # Verify specific tool has proper schema
      project_status = Enum.find(tools, &(&1["name"] == "project_status"))
      assert project_status["description"] =~ ~r/status|project/i
      assert project_status["inputSchema"]["type"] == "object"

      module_context = Enum.find(tools, &(&1["name"] == "module_context"))
      assert module_context["inputSchema"]["properties"]["module_id"]["type"] == "string"
    end
  end

  describe "tools/call project_status" do
    test "returns full project status with all fields", %{conn: conn, token: token} do
      body = %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 1,
        "params" => %{"name" => "project_status", "arguments" => %{}}
      }

      conn = mcp_post(conn, token, Jason.encode!(body))
      response = json_response(conn, 200)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"]["isError"] == false

      result = parse_mcp_result(conn)
      assert Map.has_key?(result, "project")
      assert Map.has_key?(result, "domains")
      assert Map.has_key?(result, "lint_errors")
      assert Map.has_key?(result, "stack_versions")
      assert Map.has_key?(result, "generated_at")
    end

    test "does not return only {id} field (regression for AshJsonApi serialization bug)", %{
      conn: conn,
      token: token
    } do
      body = %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 1,
        "params" => %{"name" => "project_status", "arguments" => %{}}
      }

      conn = mcp_post(conn, token, Jason.encode!(body))
      result = parse_mcp_result(conn)

      # The AshJsonApi bug returns only {id: "..."} with no other fields
      refute map_size(result) == 1 and Map.has_key?(result, "id")
    end
  end

  describe "tools/call system_graph" do
    test "returns graph with nodes and edges", %{conn: conn, token: token} do
      body = %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 2,
        "params" => %{"name" => "system_graph", "arguments" => %{}}
      }

      conn = mcp_post(conn, token, Jason.encode!(body))
      response = json_response(conn, 200)
      assert response["result"]["isError"] == false

      result = parse_mcp_result(conn)
      assert Map.has_key?(result, "nodes")
      assert Map.has_key?(result, "edges")
      assert Map.has_key?(result, "project")
      assert is_list(result["nodes"])
      assert length(result["nodes"]) > 0
    end
  end

  describe "tools/call run_lint" do
    test "returns lint result with violations list", %{conn: conn, token: token} do
      body = %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 3,
        "params" => %{"name" => "run_lint", "arguments" => %{}}
      }

      conn = mcp_post(conn, token, Jason.encode!(body))
      response = json_response(conn, 200)
      assert response["result"]["isError"] == false

      result = parse_mcp_result(conn)
      assert Map.has_key?(result, "passed")
      assert Map.has_key?(result, "error_count")
      assert Map.has_key?(result, "violations")
      assert is_list(result["violations"])
    end
  end

  describe "tools/call module_context" do
    test "returns all modules when no module_id provided", %{conn: conn, token: token} do
      body = %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 4,
        "params" => %{"name" => "module_context", "arguments" => %{}}
      }

      conn = mcp_post(conn, token, Jason.encode!(body))
      response = json_response(conn, 200)
      assert response["result"]["isError"] == false

      result = parse_mcp_result(conn)
      assert Map.has_key?(result, "id")
      assert Map.has_key?(result, "type")
      assert Map.has_key?(result, "domain")
    end

    test "returns error for unknown module", %{conn: conn, token: token} do
      body = %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 4,
        "params" => %{
          "name" => "module_context",
          "arguments" => %{"module_id" => "NonExistent.Ghost.Module"}
        }
      }

      conn = mcp_post(conn, token, Jason.encode!(body))
      response = json_response(conn, 200)
      # Should return an error result, never a crash
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 4
      assert Map.has_key?(response, "error")
    end
  end

  describe "tools/call read_doc" do
    test "returns first document when no id provided", %{conn: conn, token: token} do
      body = %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 5,
        "params" => %{"name" => "read_doc", "arguments" => %{}}
      }

      conn = mcp_post(conn, token, Jason.encode!(body))
      _ = json_response(conn, 200)

      result = parse_mcp_result(conn)
      assert Map.has_key?(result, "path")
      assert Map.has_key?(result, "title")
      assert Map.has_key?(result, "type")
    end
  end

  describe "tools/call unknown tool" do
    test "returns JSON-RPC error for unknown tool name", %{conn: conn, token: token} do
      body = %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 9,
        "params" => %{"name" => "nonexistent_tool", "arguments" => %{}}
      }

      conn = mcp_post(conn, token, Jason.encode!(body))
      response = json_response(conn, 200)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 9
      assert Map.has_key?(response, "error")
      assert response["error"]["code"] == -32_000
    end
  end

  describe "authentication" do
    test "returns 401 without auth header", %{conn: conn} do
      body = %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 1,
        "params" => %{"name" => "project_status", "arguments" => %{}}
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/foundry/mcp/", Jason.encode!(body))

      assert conn.status == 401
    end

    test "returns 401 with invalid token", %{conn: conn} do
      body = %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 1,
        "params" => %{"name" => "project_status", "arguments" => %{}}
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid_token_xyz")
        |> put_req_header("content-type", "application/json")
        |> post("/foundry/mcp/", Jason.encode!(body))

      assert conn.status == 401
    end
  end
end
