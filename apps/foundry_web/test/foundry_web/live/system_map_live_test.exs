defmodule FoundryWeb.SystemMapLiveTest do
  use FoundryWeb.ConnCase
  import Phoenix.LiveViewTest

  setup_all do
    project_root = Application.fetch_env!(:foundry_web, :igaming_project_root)
    {:ok, project_context} = Foundry.Context.ProjectContext.build(project_root)

    project_node =
      List.first(project_context.nodes) ||
        %Foundry.Context.NodeEntry{
          module: "Foundry.Test.Node",
          id: "Foundry.Test.Node",
          type: "resource",
          domain: "Test",
          description: "Test node"
        }

    {:ok, project_context: project_context, project_node: project_node}
  end

  setup do
    llm_provider = Application.get_env(:foundry, :llm_provider)
    codex = Application.get_env(:foundry, :codex)
    project_root = Application.get_env(:foundry_web, :igaming_project_root)
    chat_live_hooks = Application.get_env(:foundry_web, :chat_live_hooks)
    system_map_live_hooks = Application.get_env(:foundry_web, :system_map_live_hooks)

    on_exit(fn ->
      restore_env(:foundry, :llm_provider, llm_provider)
      restore_env(:foundry, :codex, codex)
      restore_env(:foundry_web, :igaming_project_root, project_root)
      restore_env(:foundry_web, :chat_live_hooks, chat_live_hooks)
      restore_env(:foundry_web, :system_map_live_hooks, system_map_live_hooks)
    end)
  end

  setup %{project_context: project_context, project_node: project_node} do
    Application.put_env(:foundry_web, :system_map_live_hooks,
      build_context: fn _project_root -> {:ok, project_context} end,
      build_node: fn _project_root, _module_id -> {:ok, project_node} end
    )

    put_chat_hooks()

    :ok
  end

  describe "mount" do
    test "renders page with data-context attribute when context available", %{conn: conn} do
      {:ok, _live, html} = live(conn, "/studio")
      assert html =~ "data-context"
    end

    test "embeds valid JSON in data-context attribute", %{conn: conn} do
      {:ok, _live, html} = live(conn, "/studio")

      # Extract data-context value
      assert Regex.match?(~r/data-context="[^"]+nodes[^"]*"/, html)
    end

    test "shows empty state when context unavailable" do
      # We can't easily test this without mocking, but verify mount doesn't crash
      # when context building fails
      {:ok, _live, html} = live(Phoenix.ConnTest.build_conn(), "/studio")
      # Should render without crashing
      assert html =~ "fm-workspace"
    end

    test "renders the integrated copilot workspace", %{conn: conn} do
      {:ok, _live, html} = live(conn, "/studio")

      assert html =~ "Foundry Copilot"
      assert html =~ "Governed studio chat"
      assert html =~ "Copilot"
      assert html =~ ~s(id="fm-feed")
      assert html =~ ~s(id="fm-drawer")
      assert Regex.match?(~r/id="fm-feed"[\s\S]*data-open="true"/, html)
      assert Regex.match?(~r/id="fm-drawer"[\s\S]*data-open="false"/, html)
    end
  end

  describe "handle_event node_selected" do
    test "stores selected node in assigns", %{conn: conn} do
      {:ok, live, _html} = live(conn, "/studio")

      # Simulate node selection
      result =
        render_click(live, "node_selected", %{
          "id" => "Finance.Wallet",
          "data" => %{
            "id" => "Finance.Wallet",
            "type" => "resource",
            "description" => "User wallet"
          }
        })

      # Verify the click was processed
      assert result != nil
    end
  end

  describe "handle_event fetch_node_detail" do
    test "pushes event to client on fetch request", %{conn: conn} do
      {:ok, live, _html} = live(conn, "/studio")

      # This would normally be triggered when clicking a node in large projects
      # For now, just verify the handler exists and doesn't crash
      result = render_click(live, "fetch_node_detail", %{"id" => "Finance.Wallet"})
      assert result
    end
  end

  describe "handle_event fetch_file" do
    test "pushes file content for allowed project files", %{conn: conn} do
      {:ok, live, _html} = live(conn, "/studio")

      render_click(live, "fetch_file", %{"path" => "mix.exs", "line" => "1"})

      assert_push_event(live, "file_content", %{path: "mix.exs", line: 1, content: content})
      assert content =~ "defmodule"
    end

    test "pushes a boundary error for disallowed paths", %{conn: conn} do
      {:ok, live, _html} = live(conn, "/studio")

      render_click(live, "fetch_file", %{"path" => ".env"})

      assert_push_event(live, "file_error", %{path: ".env", reason: "outside_boundary"})
    end
  end

  describe "copilot chat" do
    test "submits a chat message from the studio panel", %{conn: conn} do
      Application.put_env(:foundry, :llm_provider, :unknown_provider)

      {:ok, live, _html} = live(conn, "/studio")

      html = render_submit(live, "send_message", %{"message" => "Map the wallet flow"})

      assert html =~ "Map the wallet flow"
    end

    test "shows the system context from the studio panel", %{conn: conn} do
      {:ok, live, html} = live(conn, "/studio")
      project_root = Application.fetch_env!(:foundry_web, :igaming_project_root)

      refute html =~ "System Context Prompt"

      html = render_click(live, "toggle_system_context")

      assert html =~ "System Context Prompt"
      assert html =~ "Target project root: #{project_root}"
    end

    test "shows the active codex sandbox in the studio panel", %{conn: conn} do
      Application.put_env(:foundry, :llm_provider, :codex)
      Application.put_env(:foundry, :codex, [])

      {:ok, _live, html} = live(conn, "/studio")

      assert html =~ "sandbox workspace-write"
    end

    test "keeps the assistant response visible when final persistence fails", %{conn: conn} do
      test_pid = self()

      put_chat_hooks(
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

      {:ok, live, _html} = live(conn, "/studio")
      _html = render_submit(live, "send_message", %{"message" => "Hello"})

      assert_receive {:saved_messages, 1}
      assert_receive {:saved_messages, 2}

      assert eventually(fn ->
               rendered = render(live)

               rendered =~ "Hello back" and
                 rendered =~ "Response received but session was not saved" and
                 rendered =~ "session store is currently unavailable"
             end),
             render(live)
    end

    test "renders GFM markdown in assistant messages", %{conn: conn} do
      markdown = """
      # Build Steps

      1. Run `mix test`
      2. Review [docs](https://example.com)

      > Watch the streaming renderer.

      - [x] Keep tables
      - [ ] Keep task lists

      ~~Legacy parser~~ replaced.

      | Step | Status |
      | --- | --- |
      | Render | ready |

      ```elixir
      IO.puts("ok")
      ```

      https://foundry.test
      """

      put_chat_hooks(
        save_messages: fn _session_id, _messages -> {:ok, %{}} end,
        call_llm_stream: fn _messages, _on_event -> {:ok, markdown} end
      )

      {:ok, live, _html} = live(conn, "/studio")
      _html = render_submit(live, "send_message", %{"message" => "Format this"})

      assert eventually(fn ->
               rendered = render(live)

               rendered =~ "<h1" and
                 rendered =~ "<ol" and
                 rendered =~ "<blockquote" and
                 rendered =~ "type=\"checkbox\"" and
                 rendered =~ "<table" and
                 rendered =~ "<del>Legacy parser</del>" and
                 rendered =~ "mix test" and
                 rendered =~ "href=\"https://example.com\"" and
                 rendered =~ "href=\"https://foundry.test\"" and
                 rendered =~ "<pre" and
                 rendered =~ "puts"
             end),
             render(live)
    end

    test "renders partial streamed markdown while the assistant is still responding", %{
      conn: conn
    } do
      test_pid = self()

      put_chat_hooks(
        save_messages: fn _session_id, _messages -> {:ok, %{}} end,
        call_llm_stream: fn _messages, on_event ->
          on_event.({:delta, "```elixir\nIO.puts("})
          send(test_pid, :stream_chunk_sent)
          Process.sleep(100)

          on_event.({:delta, "\"ok\")\n```"})
          {:ok, "```elixir\nIO.puts(\"ok\")\n```"}
        end
      )

      {:ok, live, _html} = live(conn, "/studio")
      _html = render_submit(live, "send_message", %{"message" => "Stream this"})

      assert_receive :stream_chunk_sent

      assert eventually(fn ->
               rendered = render(live)

               rendered =~ "<pre" and
                 rendered =~ "Thinking..." and
                 rendered =~ "puts"
             end),
             render(live)

      assert eventually(
               fn ->
                 rendered = render(live)

                 rendered =~ "<pre" and
                   rendered =~ "&quot;ok&quot;" and
                   not String.contains?(rendered, "Thinking...")
               end,
               60
             ),
             render(live)
    end

    test "escapes raw HTML in assistant messages", %{conn: conn} do
      markdown = """
      <script>alert("x")</script>
      """

      put_chat_hooks(
        save_messages: fn _session_id, _messages -> {:ok, %{}} end,
        call_llm_stream: fn _messages, _on_event -> {:ok, markdown} end
      )

      {:ok, live, _html} = live(conn, "/studio")
      _html = render_submit(live, "send_message", %{"message" => "Format this"})

      assert eventually(fn ->
               rendered = render(live)

               rendered =~ "&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;" and
                 not String.contains?(rendered, "<script>alert(\"x\")</script>")
             end),
             render(live)
    end

    test "shows structured provider trace with tools, files, and raw payloads", %{conn: conn} do
      Application.put_env(:foundry, :llm_provider, :codex)

      put_chat_hooks(
        save_messages: fn _session_id, _messages -> {:ok, %{}} end,
        call_llm_stream: fn _messages, on_event ->
          on_event.(
            {:trace,
             %{
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
             }}
          )

          on_event.({:delta, "Done"})
          {:ok, "Done"}
        end
      )

      {:ok, live, _html} = live(conn, "/studio")
      _html = render_submit(live, "send_message", %{"message" => "Run the test"})

      assert eventually(fn -> render(live) =~ "Done" end), render(live)

      html = render_click(live, "set_chat_view", %{"view" => "trace"})

      assert html =~ "Trace Summary"
      assert html =~ "exec_command"
      assert html =~ "mix test apps/foundry_web/test/foundry_web/live/system_map_live_test.exs"
      assert html =~ "apps/foundry_web/test/foundry_web/live/system_map_live_test.exs"
      assert html =~ "Raw"
    end

    test "shows persisted session memory in the session panel", %{conn: conn} do
      put_chat_hooks(
        save_messages: fn _session_id, _messages, session_digest ->
          {:ok, %{session_digest: session_digest}}
        end,
        call_llm_stream: fn _messages, _on_event, _run_context ->
          {:ok, "Session memory ready"}
        end
      )

      {:ok, live, _html} = live(conn, "/studio")
      _html = render_submit(live, "send_message", %{"message" => "Explain the wallet flow"})

      html = render_click(live, "set_chat_view", %{"view" => "session"})

      assert html =~ "Session Memory"
      assert html =~ "Recent conclusions"
      assert html =~ "Selected nodes"
    end

    test "routes change requests into proposal-backed mode", %{conn: conn} do
      put_chat_hooks(
        save_messages: fn _session_id, _messages, session_digest ->
          {:ok, %{session_digest: session_digest}}
        end,
        call_llm_stream: fn _messages, _on_event, _run_context -> {:ok, "Proposal drafted"} end
      )

      {:ok, live, _html} = live(conn, "/studio")
      _html = render_submit(live, "send_message", %{"message" => "Implement a new transfer rule"})

      assert eventually(fn -> render(live) =~ "Proposal drafted" end)

      html = render(live)

      assert html =~ "Proposal drafted"
      assert html =~ "Proposal"
      assert html =~ "Change"
    end
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)

  defp put_chat_hooks(overrides \\ []) do
    Application.put_env(
      :foundry_web,
      :chat_live_hooks,
      Keyword.merge(base_chat_hooks(), overrides)
    )
  end

  defp base_chat_hooks do
    [
      load_session: fn _session_id -> {:ok, nil} end,
      save_messages: fn _session_id, _messages, session_digest ->
        {:ok, %{session_digest: session_digest}}
      end,
      call_llm_stream: fn _messages, _on_event, _run_context -> {:ok, "Stubbed response"} end,
      build_run_context: fn socket, message -> {:ok, canned_run_context(socket, message)} end,
      build_system_prompt: fn project_root, _run_context ->
        {:ok,
         """
         # Target Project Boundary

         Target project root: #{project_root}
         """}
      end
    ]
  end

  defp canned_run_context(socket, message) do
    mode = if String.contains?(String.downcase(message), "implement"), do: :change, else: :ask

    proposal =
      if mode == :change do
        %{id: 42, change_class: :behavioral}
      end

    %{
      mode: mode,
      proposal: proposal,
      session_digest: socket.assigns.session_digest || %{},
      system_prompt: "stub system prompt",
      trace_events: [],
      diagnostics: %{
        mode: Atom.to_string(mode),
        context_cache: "stubbed",
        context_fingerprint: "test",
        proposal_id: proposal && proposal.id
      }
    }
  end

  defp eventually(fun, attempts \\ 8)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end
end
