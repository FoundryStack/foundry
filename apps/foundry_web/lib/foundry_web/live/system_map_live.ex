defmodule FoundryWeb.SystemMapLive do
  use FoundryWeb, :live_view
  alias FoundryWeb.ChatSession
  alias FoundryWeb.ChatConfig
  alias Foundry.Context.ScenarioCache
  alias Foundry.Context.ProjectContext
  alias ExTracer.Report

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket), do: ScenarioCache.subscribe()

    hooks = Application.get_env(:foundry_web, :system_map_live_hooks, [])
    build_context = Keyword.get(hooks, :build_context, &ProjectContext.build/1)

    project_root = ChatConfig.project_root()

    # Ensure igaming ebin path is in the code path so modules can be loaded
    ebin_path = Path.join([project_root, "_build", "dev", "lib", "igaming_ref", "ebin"])

    if File.dir?(ebin_path) do
      Code.append_path(ebin_path)
    end

    project_name = Path.basename(project_root)
    preview_base_url = Foundry.PreviewServer.preview_base_url(project_root)

    case build_context.(project_root) do
      {:ok, context} ->
        nodes = context.nodes || []
        ui_nodes = Enum.map(nodes, &serialize_node/1)
        ui_edges = Enum.map(context.edges || [], &serialize_edge/1)
        context_json = Jason.encode!(%{nodes: ui_nodes, edges: ui_edges})
        report = ScenarioCache.get()
        coverage = if(report, do: report.coverage, else: %{})
        performance = if(report, do: report.performance, else: %{})
        scenario_warnings = if(report, do: report.warnings || [], else: [])
        all_scenarios = scenarios_for_context(context, report)
        node_index = scenario_node_index(report, all_scenarios)
        filtered_scenarios = all_scenarios
        scenarios_by_category = grouped_scenarios(filtered_scenarios)
        uncovered_node_ids = coverage_uncovered_node_ids(coverage)

        nodes_by_domain = build_nodes_by_domain(ui_nodes)

        # Count compliance coverage gaps: declared requirements without linked E2E coverage
        gap_count =
          Enum.count(nodes, fn n ->
            (n.compliance || []) |> Enum.any?(fn _ -> true end) and
              not n.test_coverage.e2e_tests
          end)

        # Count migrations
        migration_count = Enum.count(nodes, fn n -> n.pending_migrations end)

        # Calculate domain coverage
        domain_coverage = calculate_domain_coverage(nodes, all_scenarios)

        {:ok, socket} =
          socket
          |> assign(
            context_json: context_json,
            ui_nodes: ui_nodes,
            nodes_by_domain: nodes_by_domain,
            all_nodes: nodes,
            all_edges: context.edges || [],
            all_scenarios: all_scenarios,
            scenarios: filtered_scenarios,
            scenarios_by_category: scenarios_by_category,
            coverage: coverage,
            performance: performance,
            scenario_warnings: scenario_warnings,
            slow_test_durations: slow_test_durations(performance),
            node_index: node_index,
            uncovered_node_ids: uncovered_node_ids,
            domain_coverage: domain_coverage,
            selected_scenario_id: nil,
            active_scenario_step_id: nil,
            selected_node_scenario_count: nil,
            coverage_filtered_node: nil,
            gap_count: gap_count,
            migration_count: migration_count,
            project_name: project_name,
            sidebar_tab: :system_map,
            lens: :default,
            system_map_view: :graph,
            drawer_open: false,
            drawer_tab: :details,
            feed_open: true,
            feed_tab: :copilot,
            filter_query: "",
            selected_id: nil,
            selected_node: nil,
            project_root: project_root,
            preview_base_url: preview_base_url
          )
          |> ChatSession.mount(session)

        {:ok, socket}

      {:error, _reason} ->
        {:ok, socket} =
          socket
          |> assign(
            context_json: nil,
            ui_nodes: [],
            nodes_by_domain: %{},
            all_nodes: [],
            all_edges: [],
            all_scenarios: [],
            scenarios: [],
            scenarios_by_category: %{},
            coverage: %{},
            performance: %{},
            scenario_warnings: [],
            slow_test_durations: %{},
            node_index: %{},
            uncovered_node_ids: [],
            domain_coverage: %{},
            selected_scenario_id: nil,
            active_scenario_step_id: nil,
            selected_node_scenario_count: nil,
            coverage_filtered_node: nil,
            gap_count: 0,
            migration_count: 0,
            project_name: project_name,
            sidebar_tab: :system_map,
            lens: :default,
            system_map_view: :graph,
            drawer_open: false,
            drawer_tab: :details,
            feed_open: true,
            feed_tab: :copilot,
            filter_query: "",
            selected_id: nil,
            selected_node: nil,
            project_root: project_root,
            preview_base_url: preview_base_url
          )
          |> ChatSession.mount(session)

        {:ok, socket}
    end
  end

  @impl true
  def handle_params(%{"session" => session_id}, _uri, socket) do
    ChatSession.handle_event("chat_session_open", %{"id" => session_id}, socket)
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("chat_workspace_hydrate", params, socket) do
    ChatSession.handle_event("chat_workspace_hydrate", params, socket)
  end

  @impl true
  def handle_event("chat_session_new", params, socket) do
    case ChatSession.handle_event("chat_session_new", params, socket) do
      {:noreply, socket} ->
        active_id = socket.assigns.active_session_id

        if active_id,
          do: {:noreply, Phoenix.LiveView.push_patch(socket, to: "/?session=#{active_id}")},
          else: {:noreply, socket}
    end
  end

  @impl true
  def handle_event("chat_session_open", params, socket) do
    case ChatSession.handle_event("chat_session_open", params, socket) do
      {:noreply, socket} ->
        active_id = socket.assigns.active_session_id

        if active_id,
          do: {:noreply, Phoenix.LiveView.push_patch(socket, to: "/?session=#{active_id}")},
          else: {:noreply, socket}
    end
  end

  @impl true
  def handle_event("chat_session_switch", params, socket) do
    case ChatSession.handle_event("chat_session_switch", params, socket) do
      {:noreply, socket} ->
        active_id = socket.assigns.active_session_id

        if active_id,
          do: {:noreply, Phoenix.LiveView.push_patch(socket, to: "/?session=#{active_id}")},
          else: {:noreply, socket}
    end
  end

  @impl true
  def handle_event("chat_session_close", params, socket) do
    ChatSession.handle_event("chat_session_close", params, socket)
  end

  @impl true
  def handle_event("chat_session_rename", params, socket) do
    ChatSession.handle_event("chat_session_rename", params, socket)
  end

  @impl true
  def handle_event("chat_session_delete", params, socket) do
    ChatSession.handle_event("chat_session_delete", params, socket)
  end

  @impl true
  def handle_event("toggle_system_context", params, socket) do
    ChatSession.handle_event("toggle_system_context", params, socket)
  end

  @impl true
  def handle_event("send_message", params, socket) do
    socket = assign(socket, :feed_open, true)
    ChatSession.handle_event("send_message", params, socket)
  end

  @impl true
  def handle_event("summarize_session", params, socket) do
    ChatSession.handle_event("summarize_session", params, socket)
  end

  @impl true
  def handle_event("set_chat_view", params, socket) do
    ChatSession.handle_event("set_chat_view", params, socket)
  end

  @impl true
  def handle_event("update_chat_input", params, socket) do
    ChatSession.handle_event("update_chat_input", params, socket)
  end

  @impl true
  def handle_event("set_chat_model", params, socket) do
    ChatSession.handle_event("set_chat_model", params, socket)
  end

  @impl true
  def handle_event("proposal_apply", params, socket) do
    ChatSession.handle_event("proposal_apply", params, socket)
  end

  @impl true
  def handle_event("proposal_revise", params, socket) do
    ChatSession.handle_event("proposal_revise", params, socket)
  end

  @impl true
  def handle_event("proposal_cancel", params, socket) do
    ChatSession.handle_event("proposal_cancel", params, socket)
  end

  @impl true
  def handle_event("open_proposal_file_preview", params, socket) do
    ChatSession.handle_event("open_proposal_file_preview", params, socket)
  end

  @impl true
  def handle_event("select_activity_run", params, socket) do
    ChatSession.handle_event("select_activity_run", params, socket)
  end

  @impl true
  def handle_event("node_selected", %{"id" => node_id}, socket) do
    normalized_node_id = normalize_graph_node_id(node_id)

    socket =
      socket
      |> assign(
        selected_id: normalized_node_id,
        selected_node: normalized_node_id,
        drawer_open: true,
        drawer_tab: :details
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("show_node_coverage", %{"id" => node_id}, socket) do
    normalized_node_id = normalize_graph_node_id(node_id)

    filtered_scenarios =
      scenarios_for_selected_node(
        socket.assigns.all_scenarios,
        socket.assigns.node_index,
        normalized_node_id
      )

    filtered_scenario_ids = MapSet.new(Enum.map(filtered_scenarios, & &1.id))

    socket =
      socket
      |> assign(
        selected_id: normalized_node_id,
        selected_node: normalized_node_id,
        sidebar_tab: :test_coverage,
        coverage_filtered_node: normalized_node_id,
        selected_node_scenario_count: length(filtered_scenarios),
        scenarios: filtered_scenarios,
        scenarios_by_category: grouped_scenarios(filtered_scenarios)
      )
      |> clear_selected_scenario_if_filtered_out(filtered_scenario_ids)

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_sidebar_tab", %{"tab" => t}, socket) do
    next_socket = assign_known(socket, :sidebar_tab, t, sidebar_tabs())

    socket =
      if socket.assigns.sidebar_tab == :test_coverage and
           next_socket.assigns.sidebar_tab != :test_coverage do
        clear_scenario_state(next_socket)
      else
        next_socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_lens", %{"lens" => l}, socket) do
    {:noreply, assign_known(socket, :lens, l, lenses())}
  end

  @impl true
  def handle_event("toggle_view", _params, socket) do
    new_view = if socket.assigns.system_map_view == :graph, do: :table, else: :graph
    {:noreply, assign(socket, system_map_view: new_view)}
  end

  @impl true
  def handle_event("toggle_feed", _params, socket) do
    {:noreply, update(socket, :feed_open, &(!&1))}
  end

  @impl true
  def handle_event("toggle_copilot_sidebar", _params, socket) do
    socket =
      if socket.assigns.feed_open and socket.assigns.feed_tab == :copilot do
        assign(socket, :feed_open, false)
      else
        assign(socket, feed_open: true, feed_tab: :copilot)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_feed_tab", %{"tab" => t}, socket) do
    {:noreply, assign_known(socket, :feed_tab, t, feed_tabs())}
  end

  @impl true
  def handle_event("set_drawer_tab", %{"tab" => t}, socket) do
    {:noreply, assign_known(socket, :drawer_tab, t, drawer_tabs())}
  end

  @impl true
  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, drawer_open: false)}
  end

  @impl true
  def handle_event("filter_nodes", %{"value" => q}, socket) do
    {:noreply,
     assign(socket,
       filter_query: q,
       nodes_by_domain: build_nodes_by_domain(socket.assigns.ui_nodes, q)
     )}
  end

  @impl true
  def handle_event("fetch_node_detail", %{"id" => module_id}, socket) do
    # Above 200-module threshold path
    project_root = socket.assigns.project_root
    hooks = Application.get_env(:foundry_web, :system_map_live_hooks, [])
    build_node = Keyword.get(hooks, :build_node, &ProjectContext.build_one/2)

    case build_node.(project_root, module_id) do
      {:ok, node} ->
        {:noreply, push_event(socket, "node_detail", %{node: serialize_node(node)})}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("fetch_file", %{"path" => relative_path} = params, socket) do
    line =
      case Map.get(params, "line") do
        line when is_integer(line) and line > 0 ->
          line

        line when is_binary(line) ->
          case Integer.parse(line) do
            {value, ""} when value > 0 -> value
            _ -> nil
          end

        _ ->
          nil
      end

    case Foundry.FileSystem.read(socket.assigns.project_root, relative_path) do
      {:ok, content} ->
        {:noreply,
         push_event(socket, "file_content", %{
           path: relative_path,
           content: content,
           line: line
         })}

      {:error, reason} ->
        {:noreply,
         push_event(socket, "file_error", %{
           path: relative_path,
           reason: to_string(reason)
         })}
    end
  end

  @impl true
  def handle_event("select_scenario", %{"id" => scenario_id}, socket) do
    scenarios = socket.assigns.scenarios
    scenario = Enum.find(scenarios, &(&1.id == scenario_id))

    case scenario do
      nil ->
        {:noreply, socket}

      scen ->
        active_step_id = default_active_step_id(scen)
        payload = scenario_overlay_payload(scen, active_step_id, socket.assigns.all_edges)

        socket =
          socket
          |> assign(
            selected_scenario_id: scenario_id,
            active_scenario_step_id: active_step_id,
            drawer_open: true,
            drawer_tab: :flow
          )
          |> push_event("graph:scenario_overlay", payload)
          |> push_event("drawer:open_flow", %{})

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "select_scenario_step",
        %{"scenario_id" => scenario_id, "step_id" => step_id},
        socket
      ) do
    scenario = Enum.find(socket.assigns.scenarios, &(&1.id == scenario_id))

    case scenario do
      nil ->
        {:noreply, socket}

      scen ->
        payload = scenario_overlay_payload(scen, step_id, socket.assigns.all_edges)

        socket =
          socket
          |> assign(
            selected_scenario_id: scenario_id,
            active_scenario_step_id: step_id,
            drawer_open: true,
            drawer_tab: :flow
          )
          |> push_event("graph:scenario_overlay", payload)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_scenario", _params, socket) do
    {:noreply, clear_scenario_state(socket)}
  end

  @impl true
  def handle_event("clear_node_filter", _params, socket) do
    {:noreply,
     assign(socket,
       coverage_filtered_node: nil,
       selected_node_scenario_count: nil,
       scenarios: socket.assigns.all_scenarios,
       scenarios_by_category: grouped_scenarios(socket.assigns.all_scenarios)
     )}
  end

  @impl true
  def handle_event("stop_preview", _params, socket) do
    Foundry.PreviewServer.stop_preview()
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, _socket) do
    Foundry.PreviewServer.stop_preview()
    :ok
  end

  @impl true
  def handle_info({:scenarios_updated, report}, socket) do
    all_scenarios = List.wrap(report.scenarios)
    node_index = scenario_node_index(report, all_scenarios)

    filtered_scenarios =
      scenarios_for_selected_node(
        all_scenarios,
        node_index,
        socket.assigns.coverage_filtered_node
      )

    filtered_scenario_ids = MapSet.new(Enum.map(filtered_scenarios, & &1.id))

    {:noreply,
     socket
     |> assign(
       all_scenarios: all_scenarios,
       scenarios: filtered_scenarios,
       scenarios_by_category: grouped_scenarios(filtered_scenarios),
       coverage: report.coverage || %{},
       performance: report.performance || %{},
       scenario_warnings: report.warnings || [],
       slow_test_durations: slow_test_durations(report.performance || %{}),
       node_index: node_index,
       uncovered_node_ids: coverage_uncovered_node_ids(report.coverage || %{}),
       selected_node_scenario_count:
         if(socket.assigns.coverage_filtered_node, do: length(filtered_scenarios), else: nil)
     )
     |> clear_selected_scenario_if_filtered_out(filtered_scenario_ids)
     |> push_event("graph:coverage_overlay", %{
       uncovered_node_ids: coverage_uncovered_node_ids(report.coverage || %{})
     })
     |> push_event("graph:scenario_status_overlay", %{
       failing_node_ids: scenario_failing_node_ids(report),
       untraced_node_ids: coverage_uncovered_node_ids(report.coverage || %{})
     })}
  end

  @impl true
  def handle_info(message, socket) do
    case ChatSession.handle_info(message, socket) do
      :unhandled ->
        {:noreply, socket}

      reply ->
        reply
    end
  end

  def abbr_type(nil), do: "unk"

  def abbr_type(type) do
    case type do
      "resource" -> "res"
      "transfer" -> "trx"
      "reactor" -> "rct"
      "rule" -> "rul"
      "job" -> "job"
      "page" -> "pg"
      "liveview" -> "lv"
      "liveresource" -> "lr"
      "blueprint" -> "bp"
      "adapter" -> "adp"
      "trigger" -> "tg"
      "terminal" -> "tm"
      _ -> type |> String.slice(0..2) |> String.upcase()
    end
  end

  def type_badge_style(type) do
    {background, foreground} =
      case type do
        "resource" -> {"var(--fg-bl)", "#fff"}
        "transfer" -> {"var(--fg-gn)", "#000"}
        "reactor" -> {"var(--pu)", "#fff"}
        "rule" -> {"var(--fg-yw)", "#000"}
        "job" -> {"var(--fg-or)", "#000"}
        "page" -> {"var(--fg-page)", "#000"}
        "liveview" -> {"var(--fg-cy)", "#000"}
        "liveresource" -> {"var(--fg-pk)", "#fff"}
        "blueprint" -> {"var(--fg-or)", "#000"}
        "adapter" -> {"var(--fg-ac)", "#fff"}
        "trigger" -> {"var(--fg-ac)", "#fff"}
        "external" -> {"var(--fg-pk)", "#fff"}
        "terminal" -> {"var(--color-neutral)", "#fff"}
        _ -> {"var(--color-neutral)", "#fff"}
      end

    "--badge-bg: #{background}; --badge-fg: #{foreground};"
  end

  def type_icon_name(type) do
    case type do
      "resource" -> "hero-square-3-stack-3d-solid"
      "transfer" -> "hero-arrow-right-circle-solid"
      "reactor" -> "hero-bolt-solid"
      "rule" -> "hero-shield-check-solid"
      "job" -> "hero-clock-solid"
      "page" -> "hero-document-solid"
      "liveview" -> "hero-window-solid"
      "liveresource" -> "hero-rectangle-group-solid"
      "blueprint" -> "hero-document-duplicate-solid"
      "adapter" -> "hero-plug-solid"
      "trigger" -> "hero-play-solid"
      "terminal" -> "hero-command-line-solid"
      _ -> "hero-cube-solid"
    end
  end

  def pip_status_class(node) do
    compliance = node["compliance"] || []
    tc = node["test_coverage"] || %{}

    has_gap =
      is_list(compliance) and Enum.any?(compliance) and not Map.get(tc, "e2e_tests", false)

    cond do
      has_gap -> "bg-warning"
      node["sensitive"] -> "bg-error"
      true -> "bg-success"
    end
  end

  defp assign_known(socket, key, value, allowed) do
    case Map.fetch(allowed, value) do
      {:ok, atom_value} -> assign(socket, key, atom_value)
      :error -> socket
    end
  end

  defp sidebar_tabs do
    %{
      "system_map" => :system_map,
      "compliance" => :compliance,
      "operations" => :operations,
      "test_coverage" => :test_coverage
    }
  end

  defp lenses do
    %{
      "default" => :default,
      "trc" => :trc,
      "auth" => :auth,
      "cfg" => :cfg
    }
  end

  defp feed_tabs do
    %{
      "feed" => :feed,
      "copilot" => :copilot
    }
  end

  defp drawer_tabs do
    %{
      "details" => :details,
      "flow" => :flow,
      "shortcuts" => :shortcuts,
      "authorization" => :authorization
    }
  end

  defp panel_width_style(css_var_name, open, default_width) do
    width =
      if open do
        "var(#{css_var_name}, #{default_width}px)"
      else
        "0px"
      end

    "width: #{width};"
  end

  defp calculate_domain_coverage(nodes, scenarios) do
    domains = Enum.map(nodes, & &1.domain) |> Enum.uniq()

    domain_scores =
      Enum.reduce(domains, %{}, fn domain, acc ->
        domain_nodes = Enum.filter(nodes, &(&1.domain == domain))
        score = calculate_domain_score(domain_nodes, scenarios)

        Map.put(acc, domain, score)
      end)

    # Calculate weighted mean (all domains equal weight for now)
    overall_score =
      if Enum.empty?(domain_scores) do
        0
      else
        scores = Map.values(domain_scores)
        Enum.sum(scores) / Enum.count(scores)
      end

    domain_scores
    |> Map.put(:overall_score, overall_score)
    |> Map.put(:below_threshold, overall_score < 80)
  end

  defp calculate_domain_score([], _scenarios), do: 0

  defp calculate_domain_score(nodes, scenarios) do
    domain_node_ids =
      nodes
      |> Enum.flat_map(&[&1.id, &1.module])
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    covered_node_ids =
      scenarios
      |> Enum.flat_map(fn scenario -> List.wrap(scenario.nodes) end)
      |> Enum.map(&normalize_graph_node_id/1)
      |> Enum.filter(&MapSet.member?(domain_node_ids, &1))
      |> MapSet.new()

    covered_count = MapSet.size(covered_node_ids)
    total_count = max(length(nodes), 1)

    covered_count
    |> Kernel./(total_count)
    |> Kernel.*(100)
    |> min(100.0)
    |> max(0.0)
  end

  defp slow_test_durations(%{slowest_tests: slowest_tests}) when is_list(slowest_tests) do
    Enum.reduce(slowest_tests, %{}, fn
      {scenario_id, _test_name, duration_ms}, acc
      when is_binary(scenario_id) and is_integer(duration_ms) ->
        Map.update(acc, scenario_id, duration_ms, &max(&1, duration_ms))

      _, acc ->
        acc
    end)
  end

  defp slow_test_durations(_performance), do: %{}

  defp scenarios_for_context(_context, %Report{scenarios: report_scenarios})
       when is_list(report_scenarios) and report_scenarios != [] do
    report_scenarios
  end

  defp scenarios_for_context(context, _report), do: context.scenarios || []

  defp scenario_node_index(%Report{node_index: node_index}, _scenarios)
       when map_size(node_index) > 0,
       do: normalize_node_index(node_index)

  defp scenario_node_index(_report, scenarios), do: build_node_index(scenarios)

  defp normalize_node_index(node_index) do
    Map.new(node_index, fn {node_id, scenario_ids} ->
      {normalize_graph_node_id(node_id), Enum.uniq(List.wrap(scenario_ids))}
    end)
  end

  defp build_node_index(scenarios) do
    Enum.reduce(scenarios, %{}, fn scenario, acc ->
      Enum.reduce(List.wrap(scenario.nodes), acc, fn node_id, inner ->
        normalized_node_id = normalize_graph_node_id(node_id)
        Map.update(inner, normalized_node_id, [scenario.id], &[scenario.id | &1])
      end)
    end)
    |> Map.new(fn {node_id, scenario_ids} -> {node_id, Enum.uniq(scenario_ids)} end)
  end

  defp scenarios_for_selected_node(scenarios, _node_index, nil), do: scenarios

  defp scenarios_for_selected_node(scenarios, node_index, node_id) do
    scenario_ids =
      node_index
      |> Map.get(node_id, [])
      |> MapSet.new()

    Enum.filter(scenarios, &MapSet.member?(scenario_ids, &1.id))
  end

  defp grouped_scenarios(scenarios) do
    scenarios
    |> Enum.group_by(& &1.category)
    |> Map.new(fn {cat, scens} -> {cat, Enum.sort_by(scens, & &1.name)} end)
  end

  defp coverage_uncovered_node_ids(%{uncovered_node_ids: uncovered_node_ids})
       when is_list(uncovered_node_ids),
       do: uncovered_node_ids

  defp coverage_uncovered_node_ids(_coverage), do: []

  defp normalize_graph_node_id(graph_id) when is_binary(graph_id) do
    graph_id
    |> String.split(":step:")
    |> List.first()
    |> String.split(":action:")
    |> List.first()
    |> String.split(":state:")
    |> List.first()
  end

  defp normalize_graph_node_id(graph_id), do: graph_id

  defp clear_selected_scenario_if_filtered_out(socket, visible_scenario_ids) do
    selected_scenario_id = socket.assigns.selected_scenario_id

    if selected_scenario_id && not MapSet.member?(visible_scenario_ids, selected_scenario_id) do
      clear_scenario_state(socket)
    else
      socket
    end
  end

  defp scenario_overlay_payload(scenario, active_step_id, edges) do
    active_step = find_flow_step(scenario, active_step_id)
    overlay_transitions = build_overlay_transitions(scenario, edges)
    synthetic_transition_count = Enum.count(overlay_transitions, & &1.synthetic)
    structural_transition_count = Enum.count(overlay_transitions, &(!&1.synthetic))
    primary_test = scenario_primary_test(scenario)

    %{
      id: scenario.id,
      category: scenario.category,
      level: Map.get(scenario, :level),
      nodes: scenario.nodes,
      graph_path: scenario.graph_path,
      name: scenario.name,
      compliance_links: scenario.compliance_links,
      flow: scenario.flow,
      evidence_mode: Map.get(scenario, :evidence_mode),
      trace_status: Map.get(scenario, :trace_status),
      evidence_summary: Map.get(scenario, :evidence_summary, %{}),
      tests: Map.get(scenario, :tests, []),
      test_header: primary_test[:header],
      test_subheader: primary_test[:subheader],
      verified_test_command: primary_test[:command],
      overlay_transitions: overlay_transitions,
      overlay_edge_mode: :hybrid,
      synthetic_transition_count: synthetic_transition_count,
      structural_transition_count: structural_transition_count,
      active_step: active_step,
      active_step_id: active_step && active_step.id
    }
  end

  defp default_active_step_id(%{flow: [first_step | _]}), do: first_step.id
  defp default_active_step_id(_scenario), do: nil

  defp find_flow_step(%{flow: flow}, nil) when is_list(flow), do: List.first(flow)

  defp find_flow_step(%{flow: flow}, step_id) when is_list(flow) do
    Enum.find(flow, &(to_string(&1.id) == to_string(step_id))) || List.first(flow)
  end

  defp find_flow_step(_scenario, _step_id), do: nil

  defp build_overlay_transitions(scenario, edges) do
    evidence_mode = Map.get(scenario, :evidence_mode)
    structural_edges = structural_edge_set(edges)

    scenario
    |> overlay_transition_candidates()
    |> Enum.reduce([], fn candidate, acc ->
      transition = build_overlay_transition(candidate, evidence_mode, structural_edges)

      case transition do
        nil ->
          acc

        %{source: source, target: target} = transition ->
          case List.last(acc) do
            %{
              source: ^source,
              target: ^target,
              source_step_id: source_step_id,
              target_step_id: target_step_id,
              kind: kind,
              status: status,
              provenance: provenance
            }
            when kind == transition.kind and status == transition.status and
                   provenance == transition.provenance and
                   source_step_id == transition.source_step_id and
                   target_step_id == transition.target_step_id ->
              acc

            _ ->
              acc ++ [transition]
          end
      end
    end)
  end

  defp overlay_transition_candidates(scenario) do
    flow = List.wrap(Map.get(scenario, :flow))
    path_flow = Enum.reject(flow, &(Map.get(&1, :type) == :observation))
    graph_path = List.wrap(Map.get(scenario, :graph_path))

    consecutive_flow =
      path_flow
      |> Enum.map(&(Map.get(&1, :focus_node_id) || Map.get(&1, :node_id)))
      |> Enum.filter(& &1)
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.with_index()
      |> Enum.map(fn {[source, target], index} ->
        %{
          source: source,
          target: target,
          kind: :sequence,
          status: nil,
          provenance: flow_provenance(path_flow, source, target),
          source_step_id: step_id_at(path_flow, index),
          target_step_id: step_id_at(path_flow, index + 1)
        }
      end)

    explicit_targets =
      Enum.flat_map(path_flow, fn step ->
        source = Map.get(step, :focus_node_id) || Map.get(step, :node_id)

        step
        |> Map.get(:focus_targets, [])
        |> List.wrap()
        |> Enum.filter(& &1)
        |> Enum.map(fn target ->
          %{
            source: source,
            target: target,
            kind: Map.get(step, :kind) || Map.get(step, :type) || :transition,
            status: Map.get(step, :status),
            provenance: Map.get(step, :provenance),
            source_step_id: Map.get(step, :id),
            target_step_id: nil
          }
        end)
      end)

    contextual_step_edges =
      Enum.flat_map(path_flow, fn step ->
        source = Map.get(step, :focus_node_id) || Map.get(step, :node_id)
        target = Map.get(step, :node_id)

        if source in [nil, ""] or target in [nil, ""] or base_graph_node_id(source) == target do
          []
        else
          [
            %{
              source: source,
              target: target,
              kind: :context,
              status: Map.get(step, :status),
              provenance: Map.get(step, :provenance),
              source_step_id: Map.get(step, :id),
              target_step_id: nil
            }
          ]
        end
      end)

    graph_path_fallback =
      graph_path
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.with_index()
      |> Enum.map(fn {[source, target], index} ->
        %{
          source: source,
          target: target,
          kind: :graph_path,
          status: nil,
          provenance: if(evidence_mode(scenario) == :runtime, do: :executed, else: :expanded),
          source_step_id: "graph-path-#{index}",
          target_step_id: "graph-path-#{index + 1}"
        }
      end)

    flow_candidates = consecutive_flow ++ explicit_targets ++ contextual_step_edges

    if flow_candidates == [] do
      graph_path_fallback
    else
      flow_candidates
    end
  end

  defp flow_provenance(flow, source, target) do
    Enum.find_value(flow, :executed, fn step ->
      step_source = Map.get(step, :focus_node_id) || Map.get(step, :node_id)

      if step_source == source and target in List.wrap(Map.get(step, :focus_targets, [])) do
        Map.get(step, :provenance)
      end
    end)
  end

  defp evidence_mode(scenario), do: Map.get(scenario, :evidence_mode, :static)

  defp build_overlay_transition(
         %{source: source, target: target},
         _evidence_mode,
         _structural_edges
       )
       when source in [nil, ""] or target in [nil, ""] or source == target,
       do: nil

  defp build_overlay_transition(candidate, evidence_mode, structural_edges) do
    source_base = base_graph_node_id(candidate.source)
    target_base = base_graph_node_id(candidate.target)

    exact_match? = MapSet.member?(structural_edges, {candidate.source, candidate.target})
    normalized_match? = MapSet.member?(structural_edges, {source_base, target_base})
    synthetic? = not exact_match?

    reason =
      cond do
        exact_match? ->
          :structural_match

        normalized_match? ->
          :normalized_structural_match

        evidence_mode == :static ->
          :static_logical_transition

        true ->
          :runtime_transition_missing_structural_edge
      end

    %{
      source: candidate.source,
      target: candidate.target,
      source_base: source_base,
      target_base: target_base,
      kind: candidate.kind,
      status: candidate.status,
      provenance: candidate.provenance,
      source_step_id: Map.get(candidate, :source_step_id),
      target_step_id: Map.get(candidate, :target_step_id),
      synthetic: synthetic?,
      reason: reason
    }
  end

  defp step_id_at(flow, index) do
    flow
    |> Enum.at(index)
    |> case do
      nil -> nil
      step -> Map.get(step, :id)
    end
  end

  defp structural_edge_set(edges) do
    edges
    |> List.wrap()
    |> Enum.reduce(MapSet.new(), fn edge, acc ->
      MapSet.put(acc, {Map.get(edge, :from), Map.get(edge, :to)})
    end)
  end

  defp base_graph_node_id(graph_id) when is_binary(graph_id) do
    graph_id
    |> String.split(":step:")
    |> List.first()
    |> String.split(":action:")
    |> List.first()
  end

  defp base_graph_node_id(graph_id), do: graph_id

  defp clear_scenario_state(socket) do
    socket
    |> assign(
      selected_scenario_id: nil,
      active_scenario_step_id: nil,
      drawer_open: false,
      drawer_tab: :details
    )
    |> push_event("graph:clear_overlay", %{})
  end

  defp build_nodes_by_domain(nodes, query \\ "") do
    normalized_query = query |> to_string() |> String.trim() |> String.downcase()

    nodes
    |> Enum.filter(&node_matches_filter?(&1, normalized_query))
    |> Enum.group_by(&Map.get(&1, "domain"))
    |> Enum.map(fn {domain, ns} ->
      {domain, Enum.sort_by(ns, &display_node_label(Map.get(&1, "id")))}
    end)
    |> Enum.sort_by(fn {domain, _nodes} -> domain || "" end)
    |> Enum.into(%{})
  end

  defp node_matches_filter?(_node, ""), do: true

  defp node_matches_filter?(node, query) do
    [
      Map.get(node, "id"),
      Map.get(node, "type"),
      Map.get(node, "domain"),
      Map.get(node, "description"),
      display_node_label(Map.get(node, "id")),
      Enum.join(Map.get(node, "compliance", []), " ")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.downcase(to_string(&1)))
    |> Enum.any?(&String.contains?(&1, query))
  end

  defp serialize_node(node) do
    node
    |> Map.from_struct()
    |> Map.take([
      :id,
      :type,
      :domain,
      :description,
      :compliance,
      :test_coverage,
      :sensitive,
      :paper_trail,
      :archival,
      :data_layer,
      :rate_limited,
      :state_machine,
      :actions,
      :steps,
      :agent_steps,
      :api_routes,
      :money_attributes,
      :feature_flags,
      :runbook,
      :adrs,
      :pending_migrations,
      :last_modified,
      :schedule,
      :oban_queues,
      :performs,
      :module,
      :scenario_refs,
      :rules,
      :page_route,
      :page_group,
      :page_dynamic,
      :page_subtype,
      :calls_actions
    ])
    |> stringify_map_keys()
  end

  defp serialize_edge(edge) do
    edge
    |> Map.from_struct()
    |> Map.take([:from, :to, :relation, :step_index, :step_name, :action_name])
  end

  defp display_node_label(nil), do: nil
  defp display_node_label("external:" <> rest), do: rest

  defp display_node_label(id) do
    case String.split(id, ".") do
      [_prefix | rest] when length(rest) >= 2 -> Enum.join(rest, ".")
      _ -> id
    end
  end

  defp stringify_map_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {to_string(key), stringify_value(value)}
    end)
  end

  defp stringify_value(%_{} = value), do: value |> Map.from_struct() |> stringify_map_keys()
  defp stringify_value(value) when is_map(value), do: stringify_map_keys(value)
  defp stringify_value(value) when is_list(value), do: Enum.map(value, &stringify_value/1)
  defp stringify_value(value), do: value

  defp scenario_primary_test(scenario) do
    first_test = List.first(List.wrap(Map.get(scenario, :tests)))
    first_step = List.first(List.wrap(Map.get(scenario, :flow)))
    header = Map.get(scenario, :name) || "Scenario"
    subheader = first_step && Map.get(first_step, :test_name)
    test_file = first_test && Map.get(first_test, :file)
    test_line = first_test && Map.get(first_test, :line)

    command =
      case {test_file, test_line} do
        {file, line} when is_binary(file) and is_integer(line) -> "mix test #{file}:#{line}"
        {file, _line} when is_binary(file) -> "mix test #{file}"
        _ -> nil
      end

    %{
      header: header,
      subheader: subheader,
      command: command
    }
  end

  defp scenario_failing_node_ids(report) do
    report.scenarios
    |> List.wrap()
    |> Enum.filter(&(&1.trace_status == :failed))
    |> Enum.flat_map(&List.wrap(&1.node_ids || []))
    |> Enum.uniq()
  end
end
