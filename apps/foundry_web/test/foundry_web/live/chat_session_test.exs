defmodule FoundryWeb.ChatSessionTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  require Logger

  setup do
    # Create a minimal socket for testing without LiveView mount
    conn = build_conn()
    {:ok, conn: conn}
  end

  describe "chat message flow" do
    test "send_message triggers LLM stream with proper event handling", %{conn: conn} do
      # Set up mock LLM provider
      configure_mock_llm_provider()

      # Initialize socket manually (bypass LiveView mount for unit testing)
      session_id = Ecto.UUID.generate()
      socket = create_test_socket(session_id)

      # Send a simple message
      user_message = "What is 2 + 2?"

      # Simulate the handle_event("send_message", ...) flow
      case FoundryWeb.ChatSession.handle_event(
             "send_message",
             %{"message" => user_message},
             socket
           ) do
        {:reply, reply_payload, updated_socket} ->
          Logger.info("Send message reply: #{inspect(reply_payload)}")
          assert updated_socket.assigns.loading == true
          assert updated_socket.assigns.current_user_message == user_message

        {:noreply, _socket} ->
          flunk("Expected a reply from send_message event")
      end
    end

    test "LLM stream events accumulate and finalize correctly" do
      configure_mock_llm_provider()
      session_id = Ecto.UUID.generate()
      socket = create_test_socket(session_id)

      # Simulate receiving stream events
      socket =
        socket
        |> assign_request_state()
        |> simulate_stream_delta("Hello ")
        |> simulate_stream_delta("world!")

      # Check accumulated response
      last_message = List.last(socket.assigns.messages)
      assert last_message["role"] == "assistant"
      assert last_message["content"] == "Hello world!"
    end

    test "session persists and loads correctly" do
      session_id = Ecto.UUID.generate()
      messages = [
        %{"role" => "user", "content" => "Hello"},
        %{"role" => "assistant", "content" => "Hi there!"}
      ]

      # Save session
      FoundryWeb.ChatSessionDomainLogic.save_session_state(
        session_id,
        messages,
        %{"test" => "digest"}
      )

      # Load session
      {:ok, loaded} = FoundryWeb.ChatSessionDomainLogic.load_session(session_id)

      assert loaded["messages"] == messages
      assert loaded["session_digest"]["test"] == "digest"
    end
  end

  # Helpers

  defp create_test_socket(session_id) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        session_id: session_id,
        messages: [],
        session_digest: %{},
        error: nil,
        loading: false,
        current_user_message: nil,
        active_request_ref: nil,
        active_request_task: nil,
        project_root: test_project_root(),
        show_system_context: false,
        system_context_prompt: nil,
        system_context_error: nil,
        llm_provider: :mock,
        llm_diagnostics: %{},
        chat_view: :conversation,
        activity_runs: [],
        selected_activity_run_id: nil,
        workspace_id: Ecto.UUID.generate(),
        open_session_ids: [],
        active_session_id: nil,
        sessions_by_id: %{},
        last_session_summary_at: nil,
        live_action: :index
      }
    }
  end

  defp assign_request_state(socket) do
    ref = make_ref()

    socket
    |> Phoenix.Component.assign(:active_request_ref, ref)
    |> Phoenix.Component.assign(:messages, socket.assigns.messages ++ [
      %{"role" => "assistant", "content" => ""}
    ])
  end

  defp simulate_stream_delta(socket, delta) do
    ref = socket.assigns.active_request_ref
    messages = socket.assigns.messages

    updated_messages =
      case List.last(messages) do
        nil -> messages
        last -> Enum.slice(messages, 0..-2//-1) ++ [Map.update(last, "content", delta, &(&1 <> delta))]
      end

    Phoenix.Component.assign(socket, :messages, updated_messages)
  end

  defp configure_mock_llm_provider do
    Application.put_env(:phoenix_llm_chat, :hooks, %{
      call_llm_stream: fn _socket, _messages, _opts ->
        {:ok, make_ref()}
      end
    })
  end

  defp test_project_root do
    Path.expand("reference_projects/igaming", File.cwd!())
  end
end
