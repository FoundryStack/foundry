defmodule Foundry.ChatTraceTest do
  use ExUnit.Case, async: true

  alias Foundry.ChatTrace

  test "normalizes codex tool events with command and path details" do
    event =
      ChatTrace.normalize(:codex, %{
        "type" => "item.completed",
        "item" => %{
          "type" => "custom_tool_call",
          "name" => "exec_command",
          "arguments" => %{
            "command" =>
              "mix test apps/foundry_web/test/foundry_web/live/system_map_live_test.exs",
            "path" => "apps/foundry_web/test/foundry_web/live/system_map_live_test.exs"
          }
        }
      })

    assert event.category == :tool
    assert event.phase == :retrieval
    assert event.tool == "exec_command"
    assert event.paths == ["apps/foundry_web/test/foundry_web/live/system_map_live_test.exs"]
    assert event.title =~ "exec_command"
    assert event.detail =~ "custom_tool_call"
  end

  test "summarizes unique tools, grouped events, and surfaced files across a run" do
    events = [
      %{
        tool: "exec_command",
        paths: ["apps/foundry_web/lib/foundry_web/live/chat_session.ex"],
        phase: :retrieval,
        duplicate_key: {:retrieval, :tool, "exec_command", nil, [], "item.completed"}
      },
      %{
        tool: "exec_command",
        paths: ["apps/foundry_web/lib/foundry_web/live/chat_session.ex"],
        phase: :retrieval,
        duplicate_key: {:retrieval, :tool, "exec_command", nil, [], "item.completed"}
      },
      %{
        tool: "read_file",
        paths: ["apps/foundry/lib/foundry/codex_provider.ex"],
        phase: :shell_fallback,
        duplicate_key: {:shell_fallback, :tool, "read_file", nil, [], "item.completed"}
      }
    ]

    assert %{
             event_count: 3,
             grouped_event_count: 2,
             tool_count: 2,
             file_count: 2,
             tools: ["exec_command", "read_file"],
             files: [
               "apps/foundry_web/lib/foundry_web/live/chat_session.ex",
               "apps/foundry/lib/foundry/codex_provider.ex"
             ],
             provenance: %{shell_fallback_used: true}
           } = ChatTrace.summarize_run(events)
  end
end
