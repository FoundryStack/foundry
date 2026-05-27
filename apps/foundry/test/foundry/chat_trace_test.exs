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
        type: "foundry.context",
        provider: :foundry,
        tool: nil,
        paths: [],
        phase: :context,
        duplicate_key: {:context, :context, nil, nil, []}
      },
      %{
        type: "command_execution",
        provider: :codex,
        tool: nil,
        paths: ["apps/foundry_web/lib/foundry_web/live/chat_session.ex"],
        file_access: :read,
        phase: :shell_retrieval,
        duplicate_key:
          {:shell_retrieval, :command, nil, "rg -n bonuses lib test", []}
      },
      %{
        type: "item.completed",
        provider: :codex,
        tool: "project_status",
        paths: [],
        phase: :retrieval,
        duplicate_key: {:retrieval, :tool, "project_status", nil, []}
      },
      %{
        type: "item.completed",
        provider: :codex,
        tool: "system_graph",
        paths: [],
        phase: :retrieval,
        duplicate_key: {:retrieval, :tool, "system_graph", nil, []}
      },
      %{
        type: "command_execution",
        provider: :codex,
        tool: nil,
        paths: ["apps/foundry/lib/foundry/codex_provider.ex"],
        file_access: :write,
        phase: :shell_fallback,
        duplicate_key:
          {:shell_fallback, :command, nil, "python scratch.py", []}
      }
    ]

    summary = ChatTrace.summarize_run(events)

    assert summary.event_count == 3
    assert summary.grouped_event_count == 3
    assert summary.file_count == 2
    assert summary.read_files == ["apps/foundry_web/lib/foundry_web/live/chat_session.ex"]
    assert summary.written_files == ["apps/foundry/lib/foundry/codex_provider.ex"]
    assert summary.provenance.cached_context_used == true
    assert summary.provenance.shell_retrieval_used == true
    assert summary.provenance.true_fallback_used == true
    assert summary.provenance.shell_fallback_used == true
    assert summary.provenance.redundant_global_context_fetches == 0
  end

  test "classifies apply_patch style events as file writes" do
    event =
      ChatTrace.normalize(:codex, %{
        "type" => "item.completed",
        "item" => %{
          "type" => "custom_tool_call",
          "name" => "apply_patch",
          "arguments" => %{
            "path" => "apps/foundry_web/lib/foundry_web/live/chat_session.ex"
          }
        }
      })

    assert event.file_access == :write
  end

  test "filters out item.completed lifecycle events during summarization" do
    events = [
      %{
        type: "function_call",
        provider: :codex,
        tool: nil,
        paths: [],
        phase: :final,
        duplicate_key: {:final, :lifecycle, nil, nil, []}
      },
      %{
        type: "item.completed",
        provider: :codex,
        tool: nil,
        paths: [],
        phase: :final,
        duplicate_key: {:final, :lifecycle, nil, nil, []}
      },
      %{
        type: "function_call_output",
        provider: :codex,
        tool: nil,
        paths: [],
        phase: :final,
        duplicate_key: {:final, :lifecycle, nil, nil, []}
      }
    ]

    summary = ChatTrace.summarize_run(events)

    assert summary.event_count == 2
    assert summary.grouped_event_count == 1
    assert Enum.all?(summary.grouped_events, &(&1.type != "item.completed"))
  end

  test "deduplicates paired command events (invocation + result) into single grouped entry" do
    events = [
      %{
        type: "function_call",
        provider: :openai,
        tool: "shell",
        command: "ls -la /tmp",
        paths: ["/tmp"],
        phase: :shell_retrieval,
        duplicate_key: {:shell_retrieval, :command, "shell", "ls -la /tmp", ["/tmp"]}
      },
      %{
        type: "function_call_output",
        provider: :openai,
        tool: "shell",
        command: "ls -la /tmp",
        paths: ["/tmp"],
        phase: :shell_retrieval,
        duplicate_key: {:shell_retrieval, :command, "shell", "ls -la /tmp", ["/tmp"]}
      }
    ]

    summary = ChatTrace.summarize_run(events)

    assert summary.event_count == 2
    assert summary.grouped_event_count == 1
    grouped = List.first(summary.grouped_events)
    assert grouped.count == 2
    assert is_nil(grouped.detail)
  end

  test "does not merge events with nil duplicate_key" do
    events = [
      %{
        type: "raw_event",
        provider: :unknown,
        tool: nil,
        paths: [],
        phase: :activity,
        duplicate_key: nil
      },
      %{
        type: "raw_event",
        provider: :unknown,
        tool: nil,
        paths: [],
        phase: :activity,
        duplicate_key: nil
      }
    ]

    summary = ChatTrace.summarize_run(events)

    assert summary.event_count == 2
    assert summary.grouped_event_count == 2
  end

  test "filters out thread.started lifecycle events during summarization" do
    events = [
      %{
        type: "thread.started",
        provider: :openai,
        tool: nil,
        paths: [],
        phase: :retrieval,
        duplicate_key: nil
      },
      %{
        type: "command_execution",
        provider: :codex,
        tool: nil,
        paths: ["file.ex"],
        phase: :shell_retrieval,
        duplicate_key: {:shell_retrieval, :command, nil, "rg test", ["file.ex"]}
      },
      %{
        type: "thread.started",
        provider: :openai,
        tool: nil,
        paths: [],
        phase: :retrieval,
        duplicate_key: nil
      }
    ]

    summary = ChatTrace.summarize_run(events)

    assert summary.event_count == 1
    assert summary.grouped_event_count == 1
    assert Enum.all?(summary.grouped_events, &(&1.type != "thread.started"))
  end

  test "does not merge events with nil duplicate_key (even if phase/category match)" do
    events = [
      %{
        type: "thread.started",
        provider: :openai,
        tool: nil,
        paths: [],
        phase: :retrieval,
        duplicate_key: nil
      },
      %{
        type: "thread.started",
        provider: :openai,
        tool: nil,
        paths: [],
        phase: :retrieval,
        duplicate_key: nil
      }
    ]

    grouped = ChatTrace.grouped_timeline(events)

    # Both events should remain separate (not merged) because duplicate_key is nil
    assert length(grouped) == 2
    assert Enum.all?(grouped, &(&1.count == 1))
  end

  test "filters both item.completed and thread.started in a single run" do
    events = [
      %{
        type: "thread.started",
        provider: :openai,
        tool: nil,
        paths: [],
        phase: :retrieval,
        duplicate_key: nil
      },
      %{
        type: "command_execution",
        provider: :codex,
        tool: nil,
        paths: ["lib/bonus.ex"],
        phase: :shell_retrieval,
        duplicate_key: {:shell_retrieval, :command, nil, "rg bonus", ["lib/bonus.ex"]}
      },
      %{
        type: "item.completed",
        provider: :codex,
        tool: "project_status",
        paths: [],
        phase: :retrieval,
        duplicate_key: {:retrieval, :tool, "project_status", nil, []}
      },
      %{
        type: "thread.started",
        provider: :openai,
        tool: nil,
        paths: [],
        phase: :retrieval,
        duplicate_key: nil
      }
    ]

    summary = ChatTrace.summarize_run(events)

    # Only the command_execution event should remain
    assert summary.event_count == 1
    assert summary.grouped_event_count == 1
    assert List.first(summary.grouped_events).type == "command_execution"
  end
end
