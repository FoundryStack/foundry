defmodule FoundryWeb.ChatLiveTest do
  use FoundryWeb.ConnCase
  import Phoenix.LiveViewTest

  setup do
    llm_provider = Application.get_env(:foundry, :llm_provider)
    codex = Application.get_env(:foundry, :codex)
    lm_studio = Application.get_env(:foundry, :lm_studio)
    project_root = Application.get_env(:foundry_web, :igaming_project_root)
    chat_live_hooks = Application.get_env(:foundry_web, :chat_live_hooks)

    on_exit(fn ->
      restore_env(:foundry, :llm_provider, llm_provider)
      restore_env(:foundry, :codex, codex)
      restore_env(:foundry, :lm_studio, lm_studio)
      restore_env(:foundry_web, :igaming_project_root, project_root)
      restore_env(:foundry_web, :chat_live_hooks, chat_live_hooks)
    end)
  end

  test "does not send input changes for every typed character", %{conn: conn} do
    {:ok, _live, html} = live(conn, "/chat")

    refute html =~ ~s(phx-change="set_input")
  end

  test "submits the finished message only", %{conn: conn} do
    Application.put_env(:foundry, :llm_provider, :unknown_provider)

    {:ok, live, _html} = live(conn, "/chat")

    html =
      render_submit(live, "send_message", %{"message" => "Hello!! Tell me about the project"})

    assert html =~ "Hello!! Tell me about the project"
    refute html =~ ~s(phx-change="set_input")
  end

  test "shows the target project system context prompt", %{conn: conn} do
    {:ok, live, html} = live(conn, "/chat")

    project_root = Application.fetch_env!(:foundry_web, :igaming_project_root)

    assert html =~ project_root
    refute html =~ "System Context Prompt"

    html = render_click(live, "toggle_system_context")

    assert html =~ "System Context Prompt"
    assert html =~ "Target project root: #{project_root}"
    assert html =~ "System Architecture"
    assert html =~ "reference iGaming project"
  end

  test "context build failures are shown without crashing the live view", %{conn: conn} do
    Application.put_env(:foundry, :llm_provider, :claude_code)
    Application.put_env(:foundry_web, :igaming_project_root, System.tmp_dir!())

    {:ok, live, _html} = live(conn, "/chat")

    html = render_submit(live, "send_message", %{"message" => "Hello"})

    assert html =~ "Hello"
    assert eventually(fn -> render(live) =~ "context_build_failed" end)
  end

  test "session load failures are shown without crashing the live view", %{conn: conn} do
    Application.put_env(:foundry_web, :chat_live_hooks,
      load_session: fn _session_id -> {:error, :session_store_down} end
    )

    {:ok, _live, html} = live(conn, "/chat")

    assert html =~ "Failed to load chat session"
    assert html =~ "session_store_down"
  end

  test "lm studio connection failures are shown without crashing the live view", %{conn: conn} do
    Application.put_env(:foundry, :llm_provider, :lm_studio)

    Application.put_env(:foundry, :lm_studio,
      base_url: "http://127.0.0.1:1/v1",
      model: "local-model",
      timeout_ms: 200
    )

    {:ok, live, _html} = live(conn, "/chat")

    html = render_submit(live, "send_message", %{"message" => "Hello"})

    assert html =~ "Hello"
    assert eventually(fn -> render(live) =~ "lm_studio_error" end, 120), render(live)
  end

  test "codex unavailable is shown without crashing the live view", %{conn: conn} do
    Application.put_env(:foundry, :llm_provider, :codex)
    Application.put_env(:foundry, :codex, executable: "/missing/codex/for/test")

    {:ok, live, _html} = live(conn, "/chat")

    html = render_submit(live, "send_message", %{"message" => "Hello"})

    assert html =~ "Hello"

    assert eventually(fn -> render(live) =~ "OpenAI Codex CLI is not installed" end, 120),
           render(live)
  end

  test "initial persistence failure blocks the request and surfaces an error", %{conn: conn} do
    test_pid = self()

    Application.put_env(:foundry_web, :chat_live_hooks,
      save_messages: fn _session_id, _messages -> {:error, :session_store_down} end,
      call_llm_stream: fn _messages, _on_event ->
        send(test_pid, :llm_stream_called)
        {:ok, "should not run"}
      end
    )

    {:ok, live, _html} = live(conn, "/chat")

    html = render_submit(live, "send_message", %{"message" => "Hello"})

    assert html =~ "Failed to save chat session"
    assert html =~ "session_store_down"
    refute_received :llm_stream_called
    refute render(live) =~ "Thinking..."
  end

  test "final persistence failure keeps the response visible and marks it unsaved", %{conn: conn} do
    test_pid = self()

    Application.put_env(:foundry_web, :chat_live_hooks,
      save_messages: fn _session_id, messages ->
        send(test_pid, {:saved_messages, length(messages)})

        case length(messages) do
          1 -> {:ok, %{}}
          2 -> {:error, :session_store_down}
        end
      end,
      call_llm_stream: fn _messages, on_event ->
        on_event.({:delta, "Hello back"})
        {:ok, "Hello back"}
      end
    )

    {:ok, live, _html} = live(conn, "/chat")
    _html = render_submit(live, "send_message", %{"message" => "Hello"})

    assert_receive {:saved_messages, 1}
    assert_receive {:saved_messages, 2}

    assert eventually(
             fn ->
               rendered = render(live)

               rendered =~ "Hello back" and
                 rendered =~ "Response received but session was not saved" and
                 rendered =~ "session_store_down"
             end,
             120
           ),
           render(live)
  end

  test "replacing an in-flight request shuts down the prior chat task", %{conn: conn} do
    test_pid = self()

    Application.put_env(:foundry_web, :chat_live_hooks,
      save_messages: fn _session_id, _messages -> {:ok, %{}} end,
      call_llm_stream: fn messages, _on_event ->
        latest_message = List.last(messages)

        case latest_message["content"] do
          "Hello" ->
            send(test_pid, {:chat_task_started, :first, self()})

            receive do
              :finish_first -> {:ok, "done"}
            after
              30_000 -> {:ok, "late"}
            end

          "Again" ->
            send(test_pid, {:chat_task_started, :second, self()})
            {:ok, "done"}
        end
      end
    )

    {:ok, live, _html} = live(conn, "/chat")
    _html = render_submit(live, "send_message", %{"message" => "Hello"})

    assert_receive {:chat_task_started, :first, first_task_pid}
    monitor_ref = Process.monitor(first_task_pid)

    _html = render_submit(live, "send_message", %{"message" => "Again"})

    assert_receive {:chat_task_started, :second, _second_task_pid}
    assert_receive {:DOWN, ^monitor_ref, :process, ^first_task_pid, reason}, 1_000
    refute reason == :normal
  end

  defp eventually(fun, attempts \\ 10)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(25)
      eventually(fun, attempts - 1)
    end
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
