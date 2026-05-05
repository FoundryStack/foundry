defmodule FoundryWeb.SystemMapLive do
  use FoundryWeb, :live_view
  alias FoundryWeb.ChatSession
  alias Foundry.Context.ProjectContext

  @impl true
  def mount(_params, session, socket) do
    hooks = Application.get_env(:foundry_web, :system_map_live_hooks, [])
    build_context = Keyword.get(hooks, :build_context, &ProjectContext.build/1)

    project_root =
      Application.get_env(
        :foundry_web,
        :igaming_project_root,
        Path.expand("../../reference_projects/igaming", __DIR__)
      )

    # Ensure igaming ebin path is in the code path so modules can be loaded
    ebin_path = Path.join([project_root, "_build", "dev", "lib", "igaming_ref", "ebin"])

    if File.dir?(ebin_path) do
      Code.append_path(ebin_path)
    end

    case build_context.(project_root) do
      {:ok, context} ->
        context_json = Jason.encode!(Foundry.Context.Compact.compact(context))
        nodes = context.nodes || []
        scenarios = context.scenarios || []

        # Organize nodes by domain
        nodes_by_domain =
          Enum.group_by(nodes, & &1.domain)
          |> Enum.map(fn {domain, ns} ->
            {domain,
             Enum.map(ns, fn node ->
               node
               |> Map.from_struct()
               |> Map.new(fn {k, v} -> {to_string(k), v} end)
             end)}
          end)
          |> Enum.into(%{})

        # Organize scenarios by category
        scenarios_by_category =
          Enum.group_by(scenarios, & &1.category)
          |> Map.new(fn {cat, scens} -> {cat, Enum.sort_by(scens, & &1.name)} end)

        # Count compliance coverage gaps: declared requirements without linked E2E coverage
        gap_count =
          Enum.count(nodes, fn n ->
            (n.compliance || []) |> Enum.any?(fn _ -> true end) and
              not n.test_coverage.e2e_tests
          end)

        # Count migrations
        migration_count = Enum.count(nodes, fn n -> n.pending_migrations end)

        # Calculate domain coverage
        domain_coverage = calculate_domain_coverage(nodes, scenarios)

        {:ok, socket} =
          socket
          |> assign(
            context_json: context_json,
            nodes_by_domain: nodes_by_domain,
            all_nodes: nodes,
            all_edges: context.edges || [],
            scenarios: scenarios,
            scenarios_by_category: scenarios_by_category,
            domain_coverage: domain_coverage,
            selected_scenario_id: nil,
            active_scenario_step_id: nil,
            gap_count: gap_count,
            migration_count: migration_count,
            project_name: Path.basename(project_root),
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
            project_root: project_root
          )
          |> ChatSession.mount(session)

        {:ok, socket}

      {:error, _reason} ->
        {:ok, socket} =
          socket
          |> assign(
            context_json: nil,
            nodes_by_domain: %{},
            all_nodes: [],
            all_edges: [],
            scenarios: [],
            scenarios_by_category: %{},
            domain_coverage: %{},
            selected_scenario_id: nil,
            active_scenario_step_id: nil,
            gap_count: 0,
            migration_count: 0,
            project_name: Path.basename(project_root),
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
            project_root: project_root
          )
          |> ChatSession.mount(session)

        {:ok, socket}
    end
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
  def handle_event("set_chat_view", params, socket) do
    ChatSession.handle_event("set_chat_view", params, socket)
  end

  @impl true
  def handle_event("select_activity_run", params, socket) do
    ChatSession.handle_event("select_activity_run", params, socket)
  end

  @impl true
  def handle_event("node_selected", _params, socket) do
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
    {:noreply, assign(socket, filter_query: q)}
  end

  @impl true
  def handle_event("fetch_node_detail", %{"id" => module_id}, socket) do
    # Above 200-module threshold path
    project_root = socket.assigns.project_root
    hooks = Application.get_env(:foundry_web, :system_map_live_hooks, [])
    build_node = Keyword.get(hooks, :build_node, &ProjectContext.build_one/2)

    case build_node.(project_root, module_id) do
      {:ok, node} ->
        {:noreply, push_event(socket, "node_detail", %{node: node})}

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
  def handle_info(message, socket) do
    case ChatSession.handle_info(message, socket) do
      :unhandled -> {:noreply, socket}
      reply -> reply
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
        "resource" -> {"var(--color-info)", "#fff"}
        "transfer" -> {"var(--color-success)", "#fff"}
        "reactor" -> {"var(--pu)", "#fff"}
        "rule" -> {"var(--color-warning)", "#000"}
        "job" -> {"var(--color-error)", "#fff"}
        "liveview" -> {"#22d3ee", "#000"}
        "liveresource" -> {"#f472b6", "#fff"}
        "blueprint" -> {"#fb923c", "#000"}
        "adapter" -> {"var(--color-secondary)", "#fff"}
        "trigger" -> {"#fde047", "#000"}
        "terminal" -> {"var(--color-neutral)", "#fff"}
        _ -> {"var(--color-neutral)", "#fff"}
      end

    "--badge-bg: #{background}; --badge-fg: #{foreground};"
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
        domain_scenario_count = count_scenarios_for_domain(domain_nodes, scenarios)

        score =
          if Enum.empty?(domain_nodes), do: 0, else: min(domain_scenario_count / 4 * 100, 100)

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

  defp count_scenarios_for_domain(nodes, scenarios) do
    node_ids =
      nodes
      |> Enum.flat_map(&[&1.id, &1.module])
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    Enum.count(scenarios, fn scen ->
      Enum.any?(scen.nodes, &MapSet.member?(node_ids, &1))
    end)
  end

  defp scenario_overlay_payload(scenario, active_step_id, edges) do
    active_step = find_flow_step(scenario, active_step_id)
    overlay_transitions = build_overlay_transitions(scenario, edges)
    synthetic_transition_count = Enum.count(overlay_transitions, & &1.synthetic)
    structural_transition_count = Enum.count(overlay_transitions, &(!&1.synthetic))

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
      expansion_mode: Map.get(scenario, :expansion_mode),
      evidence_summary: Map.get(scenario, :evidence_summary, %{}),
      entry_points: Map.get(scenario, :entry_points, []),
      tests: Map.get(scenario, :tests, []),
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
              kind: kind,
              status: status,
              provenance: provenance
            }
            when kind == transition.kind and status == transition.status and
                   provenance == transition.provenance ->
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
      |> Enum.map(fn [source, target] ->
        %{
          source: source,
          target: target,
          kind: :sequence,
          status: nil,
          provenance: flow_provenance(path_flow, source, target)
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
            provenance: Map.get(step, :provenance)
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
              provenance: Map.get(step, :provenance)
            }
          ]
        end
      end)

    graph_path_fallback =
      graph_path
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [source, target] ->
        %{
          source: source,
          target: target,
          kind: :graph_path,
          status: nil,
          provenance: if(evidence_mode(scenario) == :runtime, do: :executed, else: :expanded)
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
      synthetic: synthetic?,
      reason: reason
    }
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
end
