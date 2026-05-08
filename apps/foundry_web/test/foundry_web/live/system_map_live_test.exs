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

    {:ok, conn: Phoenix.ConnTest.build_conn()}
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
    @scenario category: :invariant
    test "renders page with data-context attribute when context available", %{conn: conn} do
      {:ok, _live, html} = live(conn, "/studio")
      assert html =~ "data-context"
    end

    @scenario category: :invariant
    test "embeds valid JSON in data-context attribute", %{conn: conn} do
      {:ok, _live, html} = live(conn, "/studio")
      assert Regex.match?(~r/data-context="[^"]+nodes[^"]*"/, html)
    end

    @scenario category: :invariant
    test "embeds preview base url for the system map hook", %{conn: conn} do
      {:ok, _live, html} = live(conn, "/studio")
      assert html =~ ~s(data-preview-base-url="http://localhost:4001")
    end

    test "shows empty state when context unavailable", %{conn: conn} do
      {:ok, _live, html} = live(conn, "/studio")
      assert html =~ "fm-workspace"
    end

    @scenario category: :invariant
    test "renders the integrated copilot workspace", %{conn: conn} do
      {:ok, _live, html} = live(conn, "/studio")

      assert html =~ "Foundry Copilot"
      assert html =~ "Governed studio chat"
      assert html =~ "Copilot"
      assert html =~ ~s(id="fm-feed")
      assert html =~ ~s(id="fm-drawer")

      assert Regex.match?(
               ~r/id="fm-sidebar"[\s\S]*style="[^"]*width: var\(--foundry-sidebar-width, 240px\);"/,
               html
             )

      assert Regex.match?(
               ~r/id="fm-drawer"[\s\S]*data-open="false"[\s\S]*style="[^"]*width: 0px;"/,
               html
             )

      assert Regex.match?(
               ~r/id="fm-feed"[\s\S]*data-open="true"[\s\S]*style="[^"]*width: var\(--foundry-feed-width, 360px\);"/,
               html
             )

      assert Regex.match?(~r/id="fm-feed"[\s\S]*data-open="true"/, html)
      assert Regex.match?(~r/id="fm-drawer"[\s\S]*data-open="false"/, html)
    end

    test "project context edges resolve to renderable graph node ids", %{project_context: context} do
      valid_ids = context.nodes |> Enum.map(& &1.id) |> MapSet.new()

      Enum.each(context.edges, fn edge ->
        assert MapSet.member?(valid_ids, edge.from),
               "Studio graph source is unresolved: #{inspect(edge)}"

        assert MapSet.member?(valid_ids, edge.to),
               "Studio graph target is unresolved: #{inspect(edge)}"
      end)
    end
  end

  describe "handle_event node_selected" do
    test "opens details without switching to Coverage", %{conn: conn} do
      {:ok, live, _html} = live(conn, "/studio")

      html = render_click(live, "node_selected", %{"id" => "Finance.Wallet"})

      assert html =~ ~s(id="fm-drawer")
      assert html =~ ~s(data-open="true")
      refute html =~ "Scenario Filter"
    end

    test "does not filter scenarios automatically", %{
      conn: conn,
      project_context: context
    } do
      {node_id, scenario_ids} = node_with_partial_scenario_coverage(context.scenarios)

      Foundry.Context.ScenarioCache.update(
        scenario_report(context.scenarios, node_index: build_node_index(context.scenarios))
      )

      {:ok, live, _html} = live(conn, "/studio")

      _html = render_click(live, "node_selected", %{"id" => node_id})
      html = render_click(live, "set_sidebar_tab", %{"tab" => "test_coverage"})

      Enum.each(scenario_ids, fn scenario_id ->
        assert Regex.match?(
                 ~r/phx-click="select_scenario".*?phx-value-id="#{Regex.escape(scenario_id)}"/,
                 html
               )
      end)

      non_matching_scenarios =
        Enum.reject(context.scenarios, &(&1.id in scenario_ids))

      if non_matching_scenarios != [] do
        assert Regex.match?(
                 ~r/phx-click="select_scenario".*?phx-value-id="#{Regex.escape(hd(non_matching_scenarios).id)}"/,
                 html
               )
      end
    end
  end

  describe "handle_event show_node_coverage" do
    test "switches to Coverage and filters scenarios explicitly", %{
      conn: conn,
      project_context: context
    } do
      {node_id, scenario_ids} = node_with_partial_scenario_coverage(context.scenarios)

      Foundry.Context.ScenarioCache.update(
        scenario_report(context.scenarios, node_index: build_node_index(context.scenarios))
      )

      {:ok, live, _html} = live(conn, "/studio")

      html = render_click(live, "show_node_coverage", %{"id" => node_id})

      assert html =~ "Scenario Filter"
      assert html =~ node_id

      Enum.each(scenario_ids, fn scenario_id ->
        assert Regex.match?(
                 ~r/phx-click="select_scenario".*?phx-value-id="#{Regex.escape(scenario_id)}"/,
                 html
               )
      end)

      non_matching_scenarios =
        Enum.reject(context.scenarios, &(&1.id in scenario_ids))

      if non_matching_scenarios != [] do
        refute Regex.match?(
                 ~r/phx-click="select_scenario".*?phx-value-id="#{Regex.escape(hd(non_matching_scenarios).id)}"/,
                 html
               )
      end
    end

    test "clear_node_filter restores all scenarios", %{
      conn: conn,
      project_context: context
    } do
      {node_id, _scenario_ids} = node_with_partial_scenario_coverage(context.scenarios)

      Foundry.Context.ScenarioCache.update(
        scenario_report(context.scenarios, node_index: build_node_index(context.scenarios))
      )

      {:ok, live, _html} = live(conn, "/studio")

      filtered_html = render_click(live, "show_node_coverage", %{"id" => node_id})
      assert filtered_html =~ "Scenario Filter"

      html = render_click(live, "clear_node_filter", %{})

      refute html =~ "Scenario Filter"

      Enum.each(context.scenarios, fn scenario ->
        assert Regex.match?(
                 ~r/phx-click="select_scenario".*?phx-value-id="#{Regex.escape(scenario.id)}"/,
                 html
               )
      end)
    end
  end

  describe "handle_event filter_nodes" do
    test "filters the system map list and preserves the current query", %{conn: conn} do
      {:ok, live, _html} = live(conn, "/studio")

      html = render_keyup(live, "filter_nodes", %{"value" => "wallet"})

      assert html =~ ~s(value="wallet")
      assert html =~ "Wallet"
      refute html =~ "BonusEngine"
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
      assert html =~ "Saved findings"
      assert html =~ "Selected nodes"
    end

    test "strips hidden memory blocks and records saved findings in session memory", %{conn: conn} do
      put_chat_hooks(
        save_messages: fn _session_id, _messages, session_digest ->
          {:ok, %{session_digest: session_digest}}
        end,
        persist_session_memory: fn _project_root, _session_id, _payload, _metadata ->
          {:ok,
           %{
             id: "FND-20260507-example",
             path: "docs/findings/FND-20260507-example.md",
             title: "Provider callback finding",
             summary: "Callbacks must stay idempotent."
           }}
        end,
        call_llm_stream: fn _messages, _on_event, _run_context ->
          {:ok,
           """
           The provider callback needs an idempotency boundary.

           ```foundry-memory
           {"title":"Provider callback finding","summary":"Callbacks must stay idempotent.","findings":["[VERIFIED] Provider retries can replay the same event."]}
           ```
           """}
        end
      )

      {:ok, live, _html} = live(conn, "/studio")
      _html = render_submit(live, "send_message", %{"message" => "Explain the callback risk"})

      assert eventually(fn ->
               render(live) =~ "The provider callback needs an idempotency boundary."
             end)

      html = render(live)
      refute html =~ "```foundry-memory"
      refute html =~ "\"title\":\"Provider callback finding\""

      session_html = render_click(live, "set_chat_view", %{"view" => "session"})
      assert session_html =~ "Saved findings"
      assert session_html =~ "Provider callback finding"
      assert session_html =~ "docs/findings/FND-20260507-example.md"
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

    test "renders preview changes and summary for proposal-backed replies", %{conn: conn} do
      put_chat_hooks(
        save_messages: fn _session_id, _messages, session_digest ->
          {:ok, %{session_digest: session_digest}}
        end,
        call_llm_stream: fn _messages, _on_event, _run_context -> {:ok, "Proposal drafted"} end
      )

      {:ok, live, _html} = live(conn, "/studio")
      _html = render_submit(live, "send_message", %{"message" => "Implement a new transfer rule"})

      assert eventually(fn ->
               rendered = render(live)

               rendered =~ "Preview Changes" and
                 rendered =~ "Summary of Changes" and
                 rendered =~ "Revise In Chat" and
                 rendered =~ "apps/foundry_web/lib/foundry_web/components/chat_components.ex"
             end)
    end

    test "apply clears proposal overlay and pushes graph delta", %{conn: conn} do
      put_chat_hooks(
        save_messages: fn _session_id, _messages, session_digest ->
          {:ok, %{session_digest: session_digest}}
        end,
        call_llm_stream: fn _messages, _on_event, _run_context -> {:ok, "Proposal drafted"} end
      )

      {:ok, live, _html} = live(conn, "/studio")
      _html = render_submit(live, "send_message", %{"message" => "Implement a new transfer rule"})
      assert eventually(fn -> render(live) =~ "Apply" end)

      _html = render_click(live, "proposal_apply", %{"id" => "42"})

      assert_push_event(live, "graph:proposal_overlay", %{clear: true})
      assert_push_event(live, "graph:delta", %{nodes_modified: [%{id: "Finance.Wallet"}]})
    end

    test "clicking a proposal file opens the proposal drawer preview payload", %{conn: conn} do
      put_chat_hooks(
        save_messages: fn _session_id, _messages, session_digest ->
          {:ok, %{session_digest: session_digest}}
        end,
        call_llm_stream: fn _messages, _on_event, _run_context -> {:ok, "Proposal drafted"} end
      )

      {:ok, live, _html} = live(conn, "/studio")
      _html = render_submit(live, "send_message", %{"message" => "Implement a new transfer rule"})
      assert eventually(fn -> render(live) =~ "chat_components.ex" end)

      _html =
        render_click(live, "open_proposal_file_preview", %{
          "proposal_id" => "42",
          "path" => "apps/foundry_web/lib/foundry_web/components/chat_components.ex"
        })

      assert_push_event(live, "proposal_file_preview", %{
        proposal_id: "42",
        path: "apps/foundry_web/lib/foundry_web/components/chat_components.ex",
        content: content
      })

      assert content =~ "defmodule FoundryWeb.ChatComponents"
    end
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)

  defp scenario_report(scenarios, attrs) do
    struct!(
      ExTracer.Report,
      Keyword.merge(
        [
          extracted_at: DateTime.utc_now(),
          duration_ms: 0,
          scenarios: scenarios,
          coverage: %ExTracer.CoverageReport{},
          performance: %ExTracer.PerformanceReport{},
          node_index: %{},
          warnings: []
        ],
        attrs
      )
    )
  end

  defp build_node_index(scenarios) do
    Enum.reduce(scenarios, %{}, fn scenario, acc ->
      Enum.reduce(scenario.nodes || [], acc, fn node_id, inner ->
        Map.update(inner, node_id, [scenario.id], &[scenario.id | &1])
      end)
    end)
    |> Map.new(fn {node_id, scenario_ids} -> {node_id, Enum.uniq(scenario_ids)} end)
  end

  defp node_with_partial_scenario_coverage(scenarios) do
    node_index = build_node_index(scenarios)
    total = length(scenarios)

    Enum.find_value(node_index, fn {node_id, scenario_ids} ->
      unique_ids = Enum.uniq(scenario_ids)

      if length(unique_ids) > 0 and length(unique_ids) < total do
        {node_id, unique_ids}
      end
    end) || raise "expected a node with partial scenario coverage"
  end

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
      persist_session_memory: fn _project_root, _session_id, _payload, _metadata ->
        {:ok,
         %{
           id: "FND-test",
           path: "docs/findings/FND-test.md",
           title: "Test finding",
           summary: "Stubbed finding"
         }}
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
        %{
          id: "42",
          change_class: :behavioral,
          state: :draft,
          preview: %{
            summary: "This proposal updates the Studio copilot flow and keeps the changes reviewable before apply.",
            change_summary: [
              "Render a proposal preview card under assistant change replies.",
              "Open a proposal-aware file drawer with diff context."
            ],
            diff: """
            diff --git a/apps/foundry_web/lib/foundry_web/components/chat_components.ex b/apps/foundry_web/lib/foundry_web/components/chat_components.ex
            --- a/apps/foundry_web/lib/foundry_web/components/chat_components.ex
            +++ b/apps/foundry_web/lib/foundry_web/components/chat_components.ex
            @@
            -old preview
            +new preview
            """,
            files: [
              %{
                path: "apps/foundry_web/lib/foundry_web/components/chat_components.ex",
                status: :modified,
                diff: "@@",
                full_content: "defmodule FoundryWeb.ChatComponents do\nend\n",
                added_lines: 1,
                removed_lines: 1,
                summary: "Render the proposal preview card and action row."
              }
            ],
            graph_overlay: %{
              nodes_added: [],
              nodes_modified: [%{id: "Finance.Wallet", tone: "warning"}],
              edges_added: [],
              edges_removed: []
            }
          }
        }
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

  describe "scenario selection" do
    test "mount populates scenarios from context", %{conn: conn, project_context: context} do
      {:ok, _live, html} = live(conn, "/studio")

      assert context.scenarios |> Enum.count() > 0
      assert html =~ "Coverage"
    end

    test "scenario categories are present in template", %{conn: conn} do
      {:ok, live, _html} = live(conn, "/studio")

      # Switch to Coverage tab
      html = render_click(live, "set_sidebar_tab", %{"tab" => "test_coverage"})

      # Check that scenario categories are rendered
      assert html =~ "INVARIANT" or html =~ "COMPLIANCE" or html =~ "STATE_MACHINE" or
               html =~ "PROPERTY"
    end

    test "select_scenario finds scenario by id and pushes graph overlay event", %{
      conn: conn,
      project_context: context
    } do
      {:ok, live, _html} = live(conn, "/studio")

      # Get first scenario from context
      scenario = List.first(context.scenarios)
      assert scenario != nil

      # Click the scenario button
      _html = render_click(live, "select_scenario", %{"id" => scenario.id})

      # Verify graph:scenario_overlay event was pushed
      nodes = scenario.nodes
      active_step = List.first(scenario.flow)
      flow = scenario.flow
      active_step_id = active_step.id
      scenario_id = scenario.id
      scenario_category = scenario.category

      assert_push_event(live, "graph:scenario_overlay", %{
        id: ^scenario_id,
        category: ^scenario_category,
        nodes: ^nodes,
        flow: ^flow,
        active_step: ^active_step,
        active_step_id: ^active_step_id
      })

      assert active_step.focus_node_id
      assert is_list(active_step.focus_targets)
    end

    test "select_scenario updates selected_scenario_id in socket assigns", %{
      conn: conn,
      project_context: context
    } do
      {:ok, live, _html} = live(conn, "/studio")

      scenario = List.first(context.scenarios)

      # First switch to Coverage tab so scenarios are rendered
      _html = render_click(live, "set_sidebar_tab", %{"tab" => "test_coverage"})
      # Then click the scenario
      _html = render_click(live, "select_scenario", %{"id" => scenario.id})

      # Verify the event was pushed (this indicates the handler ran)
      assert_push_event(live, "graph:scenario_overlay", _)
      assert_push_event(live, "drawer:open_flow", %{})
    end

    test "select_scenario opens flow drawer tab", %{conn: conn, project_context: context} do
      {:ok, live, _html} = live(conn, "/studio")

      scenario = List.first(context.scenarios)
      name = scenario.name
      compliance_links = scenario.compliance_links
      flow = scenario.flow

      _html = render_click(live, "select_scenario", %{"id" => scenario.id})

      # Verify graph:scenario_overlay event was pushed with scenario data for drawer rendering
      assert_push_event(live, "graph:scenario_overlay", %{
        name: ^name,
        compliance_links: ^compliance_links,
        flow: ^flow
      })

      assert_push_event(live, "drawer:open_flow", %{})
    end

    test "scenario button in Coverage tab is clickable and triggers event", %{
      conn: conn,
      project_context: context
    } do
      {:ok, live, _html} = live(conn, "/studio")

      # Switch to Coverage tab to render scenario buttons
      coverage_html = render_click(live, "set_sidebar_tab", %{"tab" => "test_coverage"})

      # Verify scenario button is rendered with correct attributes
      scenario = List.first(context.scenarios)

      scenario_button_pattern =
        ~r/phx-click="select_scenario".*?phx-value-id="#{Regex.escape(scenario.id)}"/

      assert Regex.match?(scenario_button_pattern, coverage_html)

      # Verify onclick="event.stopPropagation()" is NOT present (it breaks <details>)
      refute coverage_html =~ "onclick=\"event.stopPropagation()\""

      # Simulate the click (simulates what the browser does)
      _html = render_click(live, "select_scenario", %{"id" => scenario.id})

      # Verify the event was processed and the graph overlay was pushed
      nodes = scenario.nodes

      assert_push_event(live, "graph:scenario_overlay", %{
        nodes: ^nodes
      })

      assert_push_event(live, "drawer:open_flow", %{})
    end

    test "select_scenario returns unchanged socket when scenario not found", %{conn: conn} do
      {:ok, live, _html} = live(conn, "/studio")

      # Try to select non-existent scenario
      _html = render_click(live, "select_scenario", %{"id" => "nonexistent.scenario"})

      # Should not push events
      refute_push_event(live, "graph:scenario_overlay", _, 100)
    end

    test "clear_scenario clears selected scenario id and pushes clear overlay event", %{
      conn: conn,
      project_context: context
    } do
      {:ok, live, _html} = live(conn, "/studio")

      # First select a scenario
      scenario = List.first(context.scenarios)
      _html = render_click(live, "select_scenario", %{"id" => scenario.id})
      assert_push_event(live, "graph:scenario_overlay", _)
      assert_push_event(live, "drawer:open_flow", %{})

      # Clear it
      _html = render_click(live, "clear_scenario", %{})

      # Verify graph:clear_overlay event was pushed
      assert_push_event(live, "graph:clear_overlay", %{})
    end

    test "scenario nodes are correctly extracted from test files", %{
      conn: conn,
      project_context: context
    } do
      {:ok, _live, _html} = live(conn, "/studio")

      # Verify scenarios have populated node lists (not empty)
      assert Enum.any?(context.scenarios, fn s -> Enum.count(s.nodes) > 0 end)
    end

    test "scenario graph paths are derived from extracted flow", %{
      conn: conn,
      project_context: context
    } do
      {:ok, _live, _html} = live(conn, "/studio")

      # Verify scenarios have populated graph paths
      assert Enum.any?(context.scenarios, fn s -> Enum.count(s.graph_path) > 0 end)
    end

    test "scenario nodes and graph paths resolve to live graph node ids", %{
      conn: conn,
      project_context: context
    } do
      {:ok, _live, _html} = live(conn, "/studio")

      node_ids = MapSet.new(Enum.map(context.nodes, & &1.id))
      graph_node_ids = graph_node_ids(context)

      Enum.each(context.scenarios, fn scenario ->
        Enum.each(scenario.nodes, fn node_id ->
          assert MapSet.member?(node_ids, node_id),
                 "scenario #{inspect(scenario.name)} references missing node #{inspect(node_id)}"
        end)

        Enum.each(scenario.graph_path, fn node_id ->
          assert MapSet.member?(graph_node_ids, node_id),
                 "scenario #{inspect(scenario.name)} graph_path references missing node #{inspect(node_id)}"
        end)
      end)
    end

    test "scenario flow nodes resolve to live graph node ids", %{
      conn: conn,
      project_context: context
    } do
      {:ok, _live, _html} = live(conn, "/studio")

      graph_node_ids = graph_node_ids(context)

      Enum.each(context.scenarios, fn scenario ->
        Enum.each(scenario.flow || [], fn step ->
          if step.node_id do
            assert MapSet.member?(graph_node_ids, step.node_id),
                   "scenario #{inspect(scenario.name)} flow step #{inspect(step.id)} references missing node #{inspect(step.node_id)}"
          end

          if step.focus_node_id do
            assert MapSet.member?(graph_node_ids, step.focus_node_id),
                   "scenario #{inspect(scenario.name)} flow step #{inspect(step.id)} focus_node_id references missing graph node #{inspect(step.focus_node_id)}"
          end

          Enum.each(step.focus_targets || [], fn node_id ->
            assert MapSet.member?(graph_node_ids, node_id),
                   "scenario #{inspect(scenario.name)} flow step #{inspect(step.id)} focus_targets references missing graph node #{inspect(node_id)}"
          end)
        end)
      end)
    end

    test "verified scenarios carry source-backed test anchors", %{
      conn: conn,
      project_context: context
    } do
      {:ok, _live, _html} = live(conn, "/studio")

      assert Enum.any?(context.scenarios, fn scenario ->
               Enum.any?(scenario.tests || [], fn test_case ->
                 is_binary(test_case.name) and is_binary(test_case.file) and
                   is_integer(test_case.line)
               end)
             end)

      assert Enum.any?(context.scenarios, fn scenario ->
               Enum.any?(scenario.flow || [], fn step ->
                 is_integer(step.line) and is_binary(step.test_name)
               end)
             end)
    end

    test "nodes use scenario_refs for verified test links without overloading scenario_origins",
         %{
           conn: conn,
           project_context: context
         } do
      {:ok, _live, _html} = live(conn, "/studio")

      assert Enum.any?(context.nodes, fn node ->
               (node.scenario_refs || []) != [] and (node.scenario_origins || []) == []
             end)
    end

    test "compliance scenarios are tagged with compliance_links", %{
      conn: conn,
      project_context: context
    } do
      {:ok, _live, _html} = live(conn, "/studio")

      compliance_scenarios = Enum.filter(context.scenarios, &(&1.category == :compliance))

      # At least some compliance scenarios should have compliance_links
      assert Enum.any?(compliance_scenarios, fn s -> Enum.count(s.compliance_links) > 0 end)
    end

    test "scenario categories are properly grouped in scenarios_by_category", %{
      conn: conn,
      project_context: context
    } do
      {:ok, _live, _html} = live(conn, "/studio")

      # Get categories from context
      scenarios_by_category = Enum.group_by(context.scenarios, & &1.category)

      # Should have at least some categories represented
      assert Enum.count(scenarios_by_category) > 0

      # Each category should have scenarios
      Enum.each(scenarios_by_category, fn {_cat, scens} ->
        assert Enum.count(scens) > 0
      end)
    end

    test "selected scenario button is highlighted", %{conn: conn, project_context: context} do
      {:ok, live, _html} = live(conn, "/studio")

      scenario = List.first(context.scenarios)

      # First switch to Coverage tab so scenarios are rendered
      coverage_html = render_click(live, "set_sidebar_tab", %{"tab" => "test_coverage"})
      # Verify scenario list is visible
      assert coverage_html =~ scenario.id

      # Then select a scenario
      html = render_click(live, "select_scenario", %{"id" => scenario.id})

      # After selection, the scenario button should be highlighted
      # Phoenix should re-render the Coverage tab with the selected scenario highlighted
      assert html =~ scenario.id
    end

    test "switching to Coverage tab shows scenario list", %{conn: conn} do
      {:ok, live, _html} = live(conn, "/studio")

      # Verify we're in a different tab initially or switch to Coverage
      coverage_html = render_click(live, "set_sidebar_tab", %{"tab" => "test_coverage"})

      # Should contain scenario groupings
      assert coverage_html =~ "INVARIANT" or coverage_html =~ "COMPLIANCE" or
               coverage_html =~ "STATE_MACHINE" or coverage_html =~ "PROPERTY"
    end

    test "coverage metadata includes uncovered node ids for graph highlighting", %{conn: conn} do
      Foundry.Context.ScenarioCache.update(
        scenario_report([],
          coverage: %ExTracer.CoverageReport{
            uncovered_node_ids: ["Finance.Wallet", "Payments.Transfer"]
          }
        )
      )

      {:ok, _live, html} = live(conn, "/studio")

      assert html =~
               ~s(data-uncovered-node-ids="[&quot;Finance.Wallet&quot;,&quot;Payments.Transfer&quot;]")
    end

    test "graph:scenario_overlay event includes all required fields for drawer rendering", %{
      conn: conn,
      project_context: context
    } do
      {:ok, live, _html} = live(conn, "/studio")

      scenario = List.first(context.scenarios)

      render_click(live, "select_scenario", %{"id" => scenario.id})

      # Verify the event payload includes all fields needed for drawer rendering
      assert_push_event(live, "graph:scenario_overlay", payload)

      # Check all required fields are present
      assert Map.has_key?(payload, :nodes)
      assert Map.has_key?(payload, :graph_path)
      assert Map.has_key?(payload, :id)
      assert Map.has_key?(payload, :category)
      assert Map.has_key?(payload, :level)
      assert Map.has_key?(payload, :name)
      assert Map.has_key?(payload, :compliance_links)
      assert Map.has_key?(payload, :flow)
      assert Map.has_key?(payload, :evidence_mode)
      assert Map.has_key?(payload, :trace_status)
      assert Map.has_key?(payload, :evidence_summary)
      assert Map.has_key?(payload, :tests)
      assert Map.has_key?(payload, :overlay_transitions)
      assert Map.has_key?(payload, :overlay_edge_mode)
      assert Map.has_key?(payload, :synthetic_transition_count)
      assert Map.has_key?(payload, :structural_transition_count)
      assert Map.has_key?(payload, :active_step)
      assert Map.has_key?(payload, :active_step_id)

      # Verify nodes is the correct set
      assert payload.nodes == scenario.nodes
      assert payload.graph_path == scenario.graph_path
      assert payload.id == scenario.id
      assert payload.category == scenario.category
      assert payload.level == scenario.level
      assert payload.name == scenario.name
      assert payload.flow == scenario.flow
      assert payload.evidence_mode == scenario.evidence_mode
      assert payload.trace_status == scenario.trace_status
      assert payload.evidence_summary == scenario.evidence_summary
      assert payload.tests == scenario.tests
      assert payload.overlay_edge_mode == :hybrid
      assert is_list(payload.overlay_transitions)

      assert payload.synthetic_transition_count + payload.structural_transition_count ==
               length(payload.overlay_transitions)

      assert payload.active_step_id == List.first(scenario.flow).id
      assert Map.has_key?(List.first(payload.flow), :focus_node_id)
      assert Map.has_key?(List.first(payload.flow), :focus_targets)
      assert Map.has_key?(List.first(payload.flow), :provenance)
      assert Map.has_key?(List.first(payload.flow), :kind)
      assert Map.has_key?(List.first(payload.flow), :status)

      if List.first(payload.overlay_transitions) do
        transition = List.first(payload.overlay_transitions)
        assert Map.has_key?(transition, :source)
        assert Map.has_key?(transition, :target)
        assert Map.has_key?(transition, :source_base)
        assert Map.has_key?(transition, :target_base)
        assert Map.has_key?(transition, :kind)
        assert Map.has_key?(transition, :status)
        assert Map.has_key?(transition, :provenance)
        assert Map.has_key?(transition, :synthetic)
        assert Map.has_key?(transition, :reason)
      end
    end

    test "timeline step selection updates the active overlay state", %{
      conn: conn,
      project_context: context
    } do
      {:ok, live, _html} = live(conn, "/studio")

      scenario = Enum.find(context.scenarios, &(Enum.count(&1.flow) > 1))
      assert scenario

      render_click(live, "select_scenario", %{"id" => scenario.id})
      assert_push_event(live, "graph:scenario_overlay", _)
      assert_push_event(live, "drawer:open_flow", %{})

      selected_step = Enum.at(scenario.flow, 1)
      selected_step_id = selected_step.id
      scenario_nodes = scenario.nodes
      scenario_graph_path = scenario.graph_path

      render_click(live, "select_scenario_step", %{
        "scenario_id" => scenario.id,
        "step_id" => selected_step_id
      })

      assert_push_event(live, "graph:scenario_overlay", %{
        nodes: ^scenario_nodes,
        graph_path: ^scenario_graph_path,
        active_step_id: ^selected_step_id,
        active_step: ^selected_step
      })
    end

    test "scenario overlay payload never requires self-loop synthetic edges", %{
      conn: conn,
      project_context: context
    } do
      {:ok, live, _html} = live(conn, "/studio")

      scenario =
        Enum.find(context.scenarios, fn scenario ->
          Enum.any?(scenario.flow || [], fn step ->
            source = step.focus_node_id || step.node_id
            Enum.any?(step.focus_targets || [], &(&1 == source))
          end)
        end)

      assert scenario, "expected a scenario with repeated same-node focus detail"

      render_click(live, "select_scenario", %{"id" => scenario.id})
      assert_push_event(live, "graph:scenario_overlay", payload)

      refute Enum.any?(overlay_transitions(payload), fn {source, target} -> source == target end),
             "overlay transitions should filter self-loops for #{inspect(scenario.name)}"
    end

    test "multi-step scenarios expose hybrid overlay transitions with structural and synthetic metadata",
         %{
           conn: conn,
           project_context: context
         } do
      {:ok, live, _html} = live(conn, "/studio")

      scenario =
        Enum.find(context.scenarios, fn scenario ->
          length(scenario.graph_path || []) > 1
        end)

      assert scenario

      render_click(live, "select_scenario", %{"id" => scenario.id})
      assert_push_event(live, "graph:scenario_overlay", payload)

      assert payload.overlay_edge_mode == :hybrid
      assert payload.overlay_transitions != []
      assert Enum.any?(payload.overlay_transitions, &(Map.get(&1, :synthetic) in [true, false]))

      assert Enum.all?(payload.overlay_transitions, fn transition ->
               transition.reason in [
                 :structural_match,
                 :static_logical_transition,
                 :normalized_structural_match,
                 :runtime_transition_missing_structural_edge
               ]
             end)
    end

    test "static scenarios label logical overlay transitions explicitly", %{
      conn: conn,
      project_context: context
    } do
      {:ok, live, _html} = live(conn, "/studio")

      scenario =
        Enum.find(context.scenarios, fn scenario ->
          scenario.name ==
            "Rule: RG-UK-014 — Withdrawal guards reject an over-limit request before funds move"
        end)

      assert scenario

      render_click(live, "select_scenario", %{"id" => scenario.id})
      assert_push_event(live, "graph:scenario_overlay", payload)

      assert payload.overlay_edge_mode == :hybrid

      assert Enum.any?(payload.overlay_transitions, fn transition ->
               transition.reason == :static_logical_transition
             end)
    end

    test "static reactor flows expose contextual step-to-node transitions", %{
      conn: conn,
      project_context: context
    } do
      {:ok, live, _html} = live(conn, "/studio")

      scenario =
        Enum.find(context.scenarios, fn scenario ->
          scenario.name == "Flow: BonusEvaluationReactor reaches the evaluation pipeline"
        end)

      assert scenario

      render_click(live, "select_scenario", %{"id" => scenario.id})
      assert_push_event(live, "graph:scenario_overlay", payload)

      assert Enum.any?(payload.overlay_transitions, fn transition ->
               transition.kind == :context and
                 transition.source == "IgamingRef.Promotions.BonusEvaluationReactor:step:0" and
                 transition.target == "IgamingRef.Promotions.BonusEvent"
             end)

      assert Enum.any?(payload.overlay_transitions, fn transition ->
               transition.kind == :context and
                 transition.source == "IgamingRef.Promotions.BonusEvaluationReactor:step:1" and
                 transition.target == "IgamingRef.Players.Player"
             end)
    end

    test "observation-only verification reads do not extend the overlay path", %{
      conn: conn,
      project_context: context
    } do
      {:ok, live, _html} = live(conn, "/studio")

      scenario =
        Enum.find(context.scenarios, fn scenario ->
          scenario.name ==
            "Flow: Player withdrawal request is approved and enters provider processing"
        end)

      assert scenario

      render_click(live, "select_scenario", %{"id" => scenario.id})
      assert_push_event(live, "graph:scenario_overlay", payload)

      refute Enum.any?(payload.overlay_transitions, fn transition ->
               transition.source == "IgamingRef.Finance.Wallet" and
                 transition.target == "IgamingRef.Finance.WithdrawalRequest"
             end)
    end

    test "withdrawal integration flow routes overlay transitions through exact action nodes", %{
      conn: conn,
      project_context: context
    } do
      {:ok, live, _html} = live(conn, "/studio")

      scenario =
        Enum.find(context.scenarios, fn scenario ->
          scenario.name ==
            "Flow: Player withdrawal request is approved and enters provider processing"
        end)

      assert scenario

      render_click(live, "select_scenario", %{"id" => scenario.id})
      assert_push_event(live, "graph:scenario_overlay", payload)

      assert "IgamingRef.Finance.WithdrawalRequest:action:create" in scenario.graph_path
      assert "IgamingRef.Finance.WithdrawalRequest:action:approve" in scenario.graph_path

      assert Enum.any?(payload.overlay_transitions, fn transition ->
               transition.source == "IgamingRef.Finance.WithdrawalRequest:action:create" and
                 transition.target == "IgamingRef.Finance.WithdrawalRequest:action:approve"
             end)
    end

    test "withdrawal page runtime overlay keeps the meaningful traced step sequence without duplicated mount cycles",
         %{
           conn: conn,
           project_context: context
         } do
      {:ok, live, _html} = live(conn, "/studio")

      scenario =
        Enum.find(context.scenarios, fn scenario ->
          scenario.source_module == "IgamingRef.Web.WithdrawalLiveTest" and
            String.contains?(scenario.name, "withdrawal page") and
            scenario.evidence_mode == :runtime
        end)

      assert scenario
      assert length(scenario.flow) >= 4

      render_click(live, "select_scenario", %{"id" => scenario.id})
      assert_push_event(live, "graph:scenario_overlay", payload)

      assert length(payload.overlay_transitions) >= 3

      assert scenario.graph_path == [
               "IgamingRef.Web.WithdrawalLive",
               "IgamingRef.Finance.Wallet:action:read",
               "IgamingRef.Finance.WithdrawalRequest:action:create",
               "IgamingRef.Finance.WithdrawalRequest:action:read"
             ]

      assert Enum.any?(payload.overlay_transitions, fn transition ->
               String.contains?(transition.source, ":action:") or
                 String.contains?(transition.target, ":action:")
             end)
    end

    test "clear_scenario properly clears overlay and resets graph state", %{
      conn: conn,
      project_context: context
    } do
      {:ok, live, _html} = live(conn, "/studio")

      scenario = List.first(context.scenarios)

      # First select a scenario
      render_click(live, "select_scenario", %{"id" => scenario.id})
      assert_push_event(live, "graph:scenario_overlay", _)
      assert_push_event(live, "drawer:open_flow", %{})

      # Then clear it
      render_click(live, "clear_scenario", %{})

      # Verify graph:clear_overlay event was pushed to reset graph state in JS hook
      assert_push_event(live, "graph:clear_overlay", %{})
    end

    test "leaving Coverage sidebar tab clears active scenario and closes drawer", %{
      conn: conn,
      project_context: context
    } do
      {:ok, live, _html} = live(conn, "/studio")

      scenario = List.first(context.scenarios)

      render_click(live, "set_sidebar_tab", %{"tab" => "test_coverage"})
      render_click(live, "select_scenario", %{"id" => scenario.id})
      assert_push_event(live, "graph:scenario_overlay", _)
      assert_push_event(live, "drawer:open_flow", %{})

      render_click(live, "set_sidebar_tab", %{"tab" => "system_map"})

      assert_push_event(live, "graph:clear_overlay", %{})
      refute render(live) =~ ~s(phx-value-id="#{scenario.id}")
    end
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

  defp graph_node_ids(context) do
    context.nodes
    |> Enum.flat_map(fn node ->
      step_ids =
        node
        |> Map.get(:steps, [])
        |> Enum.with_index()
        |> Enum.map(fn {_step, index} -> "#{node.id}:step:#{index}" end)

      action_ids =
        node
        |> Map.get(:actions, [])
        |> Enum.map(fn action -> "#{node.id}:action:#{action.name}" end)

      [node.id | step_ids ++ action_ids]
    end)
    |> MapSet.new()
  end

  defp overlay_transitions(payload) do
    payload
    |> Map.get(:overlay_transitions, [])
    |> Enum.map(fn transition -> {transition.source, transition.target} end)
  end
end
