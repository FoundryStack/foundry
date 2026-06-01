defmodule FoundryWeb.ChatSessionTabManagerTest do
  use ExUnit.Case, async: true

  alias FoundryWeb.ChatSessionTabManager, as: TabManager

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp make_socket(assigns) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns)
    }
  end

  defp base_assigns(overrides \\ %{}) do
    Map.merge(
      %{
        active_session_id: "sess-1",
        open_session_ids: ["sess-1"],
        messages: [],
        chat_loading: false,
        active_request_ref: nil,
        active_request_task: nil,
        pending_messages: [],
        session_digest: %{},
        activity_runs: [],
        selected_activity_run_id: nil,
        error: nil,
        input: "",
        per_session_state: %{},
        session_inputs: %{}
      },
      overrides
    )
  end

  # ---------------------------------------------------------------------------
  # find_background_session_for_request/2
  # ---------------------------------------------------------------------------

  describe "find_background_session_for_request/2" do
    test "returns {session_id, state} when request_ref found" do
      ref = make_ref()
      state = %{active_request_ref: ref, messages: [], chat_loading: true}
      per_session_state = %{"sess-bg" => state}

      assert {session_id, ^state} =
               TabManager.find_background_session_for_request(per_session_state, ref)

      assert session_id == "sess-bg"
    end

    test "returns nil when request_ref not found" do
      ref = make_ref()
      other_ref = make_ref()
      state = %{active_request_ref: other_ref, messages: []}
      per_session_state = %{"sess-bg" => state}

      assert TabManager.find_background_session_for_request(per_session_state, ref) == nil
    end

    test "returns nil on empty map" do
      assert TabManager.find_background_session_for_request(%{}, make_ref()) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # resolve_selected_model/2
  # ---------------------------------------------------------------------------

  describe "resolve_selected_model/2" do
    defp mock_catalog do
      %{
        models: [
          %{id: "claude-code", provider: :claude_code, model_id: "claude-3-5"},
          %{id: "gemini", provider: :gemini, model_id: "gemini-pro"}
        ],
        default_id: "claude-code"
      }
    end

    defmodule MockCatalog do
      def get(%{models: models}, id), do: Enum.find(models, &(&1.id == id))
      def default_model_id(%{default_id: id}), do: id
    end

    test "returns model for given id" do
      catalog = mock_catalog()
      result = MockCatalog.get(catalog, "gemini")
      assert result.provider == :gemini
    end

    test "falls back to default when id is nil" do
      catalog = mock_catalog()
      result = MockCatalog.get(catalog, MockCatalog.default_model_id(catalog))
      assert result.id == "claude-code"
    end
  end

  # ---------------------------------------------------------------------------
  # save_active_session_state/1
  # ---------------------------------------------------------------------------

  describe "save_active_session_state/1" do
    test "snapshots current session into per_session_state" do
      messages = [%{"id" => "m1", "role" => "user", "content" => "hello"}]

      socket =
        make_socket(base_assigns(%{messages: messages, input: "draft text", active_session_id: "sess-1"}))

      updated = TabManager.save_active_session_state(socket)
      state = updated.assigns.per_session_state["sess-1"]

      assert state.messages == messages
      assert state.chat_loading == false
      assert updated.assigns.session_inputs["sess-1"] == "draft text"
    end

    test "no-ops when active_session_id is nil" do
      socket = make_socket(base_assigns(%{active_session_id: nil}))
      updated = TabManager.save_active_session_state(socket)
      assert updated.assigns.per_session_state == %{}
    end

    test "no-ops when active_session_id not in open_session_ids" do
      socket =
        make_socket(base_assigns(%{active_session_id: "sess-1", open_session_ids: ["sess-2"]}))

      updated = TabManager.save_active_session_state(socket)
      assert updated.assigns.per_session_state == %{}
    end
  end

  # ---------------------------------------------------------------------------
  # restore_session_state/2
  # ---------------------------------------------------------------------------

  describe "restore_session_state/2" do
    test "returns socket unchanged when session_id is nil" do
      socket = make_socket(base_assigns())
      assert TabManager.restore_session_state(socket, nil) == socket
    end

    test "restores state from per_session_state when present" do
      ref = make_ref()
      pid = spawn(fn -> Process.sleep(:infinity) end)
      task = %{pid: pid}

      saved_state = %{
        messages: [%{"id" => "m1", "role" => "user", "content" => "hi"}],
        chat_loading: true,
        active_request_ref: ref,
        active_request_task: task,
        pending_messages: [],
        session_digest: %{"retrieval_mode" => "ask"},
        activity_runs: [],
        selected_activity_run_id: nil,
        error: nil
      }

      socket =
        make_socket(
          base_assigns(%{
            per_session_state: %{"sess-2" => saved_state},
            session_inputs: %{"sess-2" => "my draft"}
          })
        )

      updated = TabManager.restore_session_state(socket, "sess-2")
      assert updated.assigns.messages == saved_state.messages
      assert updated.assigns.chat_loading == true
      assert updated.assigns.active_request_ref == ref
      assert updated.assigns.input == "my draft"

      Process.exit(pid, :kill)
    end

    test "clears active task refs when task process is dead" do
      dead_pid = spawn(fn -> :ok end)
      Process.sleep(5)

      saved_state = %{
        messages: [],
        chat_loading: true,
        active_request_ref: make_ref(),
        active_request_task: %{pid: dead_pid},
        pending_messages: [],
        session_digest: %{},
        activity_runs: [],
        selected_activity_run_id: nil,
        error: nil
      }

      socket =
        make_socket(base_assigns(%{per_session_state: %{"sess-2" => saved_state}}))

      updated = TabManager.restore_session_state(socket, "sess-2")
      assert updated.assigns.chat_loading == false
      assert updated.assigns.active_request_ref == nil
      assert updated.assigns.active_request_task == nil
    end
  end
end
