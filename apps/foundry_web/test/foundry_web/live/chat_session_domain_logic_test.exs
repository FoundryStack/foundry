defmodule FoundryWeb.ChatSessionDomainLogicTest do
  use ExUnit.Case, async: true

  alias FoundryWeb.ChatSessionDomainLogic, as: DomainLogic

  # ---------------------------------------------------------------------------
  # normalize_session_digest/1
  # ---------------------------------------------------------------------------

  describe "normalize_session_digest/1" do
    test "nil returns empty map" do
      assert DomainLogic.normalize_session_digest(nil) == %{}
    end

    test "valid map passes through unchanged" do
      digest = %{"retrieval_mode" => "ask", "active_proposal_id" => "abc"}
      assert DomainLogic.normalize_session_digest(digest) == digest
    end

    test "non-map non-nil returns empty map" do
      assert DomainLogic.normalize_session_digest("garbage") == %{}
      assert DomainLogic.normalize_session_digest(42) == %{}
      assert DomainLogic.normalize_session_digest([]) == %{}
    end
  end

  # ---------------------------------------------------------------------------
  # prepare_session_digest/4
  # ---------------------------------------------------------------------------

  describe "prepare_session_digest/4" do
    defp mock_retrieval(cache \\ :miss, fingerprint \\ "fp-123") do
      %{
        cached_context: %{cache: cache, fingerprint: fingerprint},
        trace_events: []
      }
    end

    test "sets retrieval_mode, fingerprint, and nil proposal_draft" do
      digest = DomainLogic.prepare_session_digest(%{}, mock_retrieval(), :ask, nil)
      assert digest["retrieval_mode"] == "ask"
      assert digest["cached_context_fingerprint"] == "fp-123"
      assert digest["proposal_draft"] == nil
    end

    test "stores stringified proposal when mode is :change" do
      proposal = %{id: "p-1", title: "My change", status: :pending}
      digest = DomainLogic.prepare_session_digest(%{}, mock_retrieval(), :change, proposal)
      assert digest["retrieval_mode"] == "change"
      assert is_map(digest["proposal_draft"])
    end

    test "preserves existing digest keys" do
      base = %{"session_label_locked" => true, "recent_files" => ["lib/foo.ex"]}
      digest = DomainLogic.prepare_session_digest(base, mock_retrieval(), :ask, nil)
      assert digest["session_label_locked"] == true
      assert digest["recent_files"] == ["lib/foo.ex"]
    end
  end

  # ---------------------------------------------------------------------------
  # update_latest_proposal_message/3
  # ---------------------------------------------------------------------------

  defp msg(id, proposal_id) do
    %{
      "id" => id,
      "role" => "assistant",
      "content" => "response",
      "proposal" => %{"id" => proposal_id, "status" => "pending"}
    }
  end

  describe "update_latest_proposal_message/3" do
    test "updates status of the matching proposal message" do
      messages = [msg("m1", "p-1"), msg("m2", "p-2")]
      updated = DomainLogic.update_latest_proposal_message(messages, "p-1", :applied)
      assert get_in(updated, [Access.at(0), "proposal", "status"]) == "applied"
      assert get_in(updated, [Access.at(1), "proposal", "status"]) == "pending"
    end

    test "updates the latest (last-indexed) message when duplicate proposal ids exist" do
      messages = [msg("m1", "p-1"), msg("m2", "p-1")]
      updated = DomainLogic.update_latest_proposal_message(messages, "p-1", :cancelled)
      assert get_in(updated, [Access.at(1), "proposal", "status"]) == "cancelled"
      assert get_in(updated, [Access.at(0), "proposal", "status"]) == "pending"
    end

    test "returns messages unchanged when proposal_id not found" do
      messages = [msg("m1", "p-1")]
      assert DomainLogic.update_latest_proposal_message(messages, "p-999", :applied) == messages
    end

    test "handles empty messages list" do
      assert DomainLogic.update_latest_proposal_message([], "p-1", :applied) == []
    end
  end

  # ---------------------------------------------------------------------------
  # find_proposal/2
  # ---------------------------------------------------------------------------

  describe "find_proposal/2" do
    test "finds proposal by id from message" do
      messages = [
        %{"id" => "m1", "role" => "assistant", "content" => "x",
          "proposal" => %{"id" => "p-1", "title" => "T"}},
        %{"id" => "m2", "role" => "user", "content" => "y"}
      ]
      proposal = DomainLogic.find_proposal(messages, "p-1")
      assert proposal["title"] == "T"
    end

    test "returns nil when not found" do
      assert DomainLogic.find_proposal([], "p-999") == nil
    end
  end

  # ---------------------------------------------------------------------------
  # append_trace_event_to_run/2
  # ---------------------------------------------------------------------------

  defp minimal_run do
    %{
      stream_cursor: 0,
      events: [],
      grouped_events: [],
      phase_groups: [],
      phase_counts: %{},
      event_count: 0,
      grouped_event_count: 0,
      tool_count: 0,
      file_count: 0,
      tools: [],
      files: [],
      read_files: [],
      written_files: []
    }
  end

  describe "append_trace_event_to_run/2" do
    test "prepends event to run.events" do
      run = DomainLogic.append_trace_event_to_run(minimal_run(), %{"type" => "text", "message" => "hello"})
      assert length(run.events) == 1
      assert hd(run.events).type == "text"
    end

    test "stamped event includes text_cursor from stream_cursor" do
      run = Map.put(minimal_run(), :stream_cursor, 7)
      updated = DomainLogic.append_trace_event_to_run(run, %{"type" => "text"})
      assert hd(updated.events).text_cursor == 7
    end

    test "caps events at 250" do
      run =
        Enum.reduce(1..260, minimal_run(), fn i, acc ->
          DomainLogic.append_trace_event_to_run(acc, %{"type" => "text", "message" => "event #{i}"})
        end)

      assert length(run.events) == 250
    end

    test "summary fields are merged into run" do
      run = DomainLogic.append_trace_event_to_run(minimal_run(), %{"type" => "text"})
      assert Map.has_key?(run, :event_count)
    end
  end

  # ---------------------------------------------------------------------------
  # proposal_file_preview_payload/3
  # ---------------------------------------------------------------------------

  describe "proposal_file_preview_payload/3" do
    defp messages_with_proposal(files) do
      [
        %{
          "id" => "m1",
          "role" => "assistant",
          "content" => "ok",
          "proposal" => %{
            "id" => "p-1",
            "preview" => %{"files" => files}
          }
        }
      ]
    end

    test "returns nil when proposal not found" do
      assert DomainLogic.proposal_file_preview_payload([], "p-999", "lib/foo.ex") == nil
    end

    test "returns nil when proposal has no matching file" do
      msgs = messages_with_proposal([])
      assert DomainLogic.proposal_file_preview_payload(msgs, "p-1", "lib/foo.ex") == nil
    end

    test "returns preview payload for matching file path" do
      files = [%{path: "lib/foo.ex", preview: "diff content", language: "elixir"}]
      msgs = [
        %{
          "id" => "m1",
          "role" => "assistant",
          "content" => "ok",
          "proposal" => %{
            "id" => "p-1",
            "created_files" => files
          }
        }
      ]
      result = DomainLogic.proposal_file_preview_payload(msgs, "p-1", "lib/foo.ex")
      assert result.path == "lib/foo.ex"
      assert result.preview == "diff content"
      assert result.language == "elixir"
    end
  end

  # ---------------------------------------------------------------------------
  # create_activity_run/5
  # ---------------------------------------------------------------------------

  describe "create_activity_run/5" do
    defp fake_run_context do
      %{
        mode: :ask,
        proposal: nil,
        diagnostics: %{mode: "ask"}
      }
    end

    test "returns map with required fields set" do
      run =
        DomainLogic.create_activity_run(
          "hello",
          make_ref(),
          fake_run_context(),
          fn -> :claude_code end,
          fn extra -> Map.merge(%{provider: :claude_code}, extra) end
        )

      assert run.status == :running
      assert run.stream_cursor == 0
      assert run.events == []
      assert run.mode == :ask
      assert run.user_message == "hello"
      assert run.provider == :claude_code
      assert is_binary(run.started_at)
      assert is_nil(run.finished_at)
    end

    test "each call produces a unique id" do
      ref1 = make_ref()
      ref2 = make_ref()
      ctx = fake_run_context()

      run1 = DomainLogic.create_activity_run("a", ref1, ctx, fn -> :gemini end, fn e -> e end)
      run2 = DomainLogic.create_activity_run("b", ref2, ctx, fn -> :gemini end, fn e -> e end)

      assert run1.id != run2.id
    end
  end
end
