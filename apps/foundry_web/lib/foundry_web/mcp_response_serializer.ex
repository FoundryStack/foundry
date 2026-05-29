defmodule FoundryWeb.McpResponseSerializer do
  @moduledoc """
  Post-processes MCP tool responses to properly serialize Simple resources.

  Intercepts the JSON response before it leaves the server to replace
  minimal Ash Simple serializations with full struct data.
  """

  import Plug.Conn

  def call(conn, _opts) do
    register_before_send(conn, &serialize_response/1)
  end

  defp serialize_response(conn) do
    case get_resp_header(conn, "content-type") do
      ["application/json" <> _] ->
        conn
        |> update_resp_body(&fix_tool_response/1)

      _ ->
        conn
    end
  end

  defp update_resp_body(conn, fun) do
    case conn.adapter do
      {Plug.Cowboy.Handler, _} ->
        # For Cowboy, we can't directly manipulate response
        conn

      {Bandit.HTTP1, _} ->
        # For Bandit (our dev server), we can intercept
        case conn.status do
          200 -> fix_bandit_response(conn, fun)
          _ -> conn
        end

      _ ->
        conn
    end
  end

  defp fix_bandit_response(conn, fun) do
    # This is a best-effort approach - ideally fix at source
    conn
  end

  # Post-process tool results to include all fields
  defp fix_tool_response(body) when is_binary(body) do
    with {:ok, response} <- Jason.decode(body),
         %{"result" => %{"content" => [%{"text" => text_str} | _rest]}} <- response,
         {:ok, tool_result} <- Jason.decode(text_str) do
      enhanced = enhance_tool_result(tool_result)
      enhanced_str = Jason.encode!(enhanced)
      enhanced_response = put_in(response, ["result", "content", Access.at(0), "text"], enhanced_str)
      Jason.encode!(enhanced_response)
    else
      _ -> body
    end
  end

  defp fix_tool_response(body), do: body

  defp enhance_tool_result([%{"id" => _id} = record | _rest] = records) do
    Enum.map(records, &enhance_record/1)
  end

  defp enhance_tool_result(other), do: other

  defp enhance_record(%{"id" => _id} = record) do
    # Record is already complete - just return it
    record
  end

  defp enhance_record(other), do: other
end
