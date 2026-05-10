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

  test "classifies governed shell inspection as shell retrieval" do
    event =
      ChatTrace.normalize(:codex, %{
        "type" => "command_execution",
        "command" =>
          ~s(/bin/zsh -lc "rg -n \\"bonus\\" lib test docs/runbooks && sed -n '1,220p' lib/bonus.ex")
      })

    assert event.category == :command
    assert event.phase == :shell_retrieval
    assert ChatTrace.phase_label(event.phase) == "Shell Retrieval"
    assert event.title =~ "Inspected via shell"
  end

  test "keeps explicit degraded shell commands as shell fallback" do
    event =
      ChatTrace.normalize(:codex, %{
        "type" => "command_execution",
        "command" => ~s(/bin/zsh -lc "python scratch.py"),
        "message" => "Ran fallback command because structured retrieval was unavailable"
      })

    assert event.phase == :shell_fallback
    assert ChatTrace.phase_label(event.phase) == "Shell Fallback"
    assert event.title =~ "Ran fallback command"
  end

  test "summarizes shell retrieval, true fallback, and redundant global fetches across a run" do
    events = [
      %{
        provider: :foundry,
        tool: nil,
        paths: [],
        phase: :context,
        duplicate_key: {:context, :context, nil, nil, [], "foundry.context"}
      },
      %{
        provider: :codex,
        tool: nil,
        paths: ["apps/foundry_web/lib/foundry_web/live/chat_session.ex"],
        phase: :shell_retrieval,
        duplicate_key:
          {:shell_retrieval, :command, nil, "rg -n bonuses lib test", [], "command_execution"}
      },
      %{
        provider: :codex,
        tool: "project_status",
        paths: [],
        phase: :retrieval,
        duplicate_key: {:retrieval, :tool, "project_status", nil, [], "item.completed"}
      },
      %{
        provider: :codex,
        tool: "system_graph",
        paths: [],
        phase: :retrieval,
        duplicate_key: {:retrieval, :tool, "system_graph", nil, [], "item.completed"}
      },
      %{
        provider: :codex,
        tool: nil,
        paths: ["apps/foundry/lib/foundry/codex_provider.ex"],
        phase: :shell_fallback,
        duplicate_key:
          {:shell_fallback, :command, nil, "python scratch.py", [], "command_execution"}
      }
    ]

    assert %{
             event_count: 5,
             grouped_event_count: 5,
             file_count: 2,
             provenance: %{
               cached_context_used: true,
               shell_retrieval_used: true,
               true_fallback_used: true,
               shell_fallback_used: true,
               redundant_global_context_fetches: 2
             }
           } = ChatTrace.summarize_run(events)
  end
end
