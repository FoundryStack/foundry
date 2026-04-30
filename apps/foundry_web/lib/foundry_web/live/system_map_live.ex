defmodule FoundryWeb.SystemMapLive do
  use FoundryWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    project_root = Application.get_env(:foundry_web, :igaming_project_root,
      Path.expand("../../reference_projects/igaming", __DIR__))

    # Ensure igaming ebin path is in the code path so modules can be loaded
    ebin_path = Path.join([project_root, "_build", "dev", "lib", "igaming_ref", "ebin"])
    if File.dir?(ebin_path) do
      Code.append_path(ebin_path)
    end

    case Foundry.Context.ProjectContext.build(project_root) do
      {:ok, context} ->
        context_json = Jason.encode!(Foundry.Context.Compact.compact(context))
        nodes = context.nodes || []

        # Organize nodes by domain
        nodes_by_domain = Enum.group_by(nodes, & &1.domain)
          |> Enum.map(fn {domain, ns} ->
            {domain, Enum.map(ns, fn node ->
              node
              |> Map.from_struct()
              |> Map.new(fn {k, v} -> {to_string(k), v} end)
            end)}
          end)
          |> Enum.into(%{})

        # Count gaps: compliance reqs + no E2E tests
        gap_count = Enum.count(nodes, fn n ->
          (n.compliance || []) |> Enum.any?(fn _ -> true end) and
            not n.test_coverage.e2e_tests
        end)

        # Count migrations
        migration_count = Enum.count(nodes, fn n -> n.pending_migrations end)

        {:ok, assign(socket,
          context_json: context_json,
          nodes_by_domain: nodes_by_domain,
          all_nodes: nodes,
          gap_count: gap_count,
          migration_count: migration_count,
          project_name: Path.basename(project_root),
          sidebar_tab: :system_map,
          lens: :default,
          system_map_view: :graph,
          drawer_open: false,
          drawer_tab: :details,
          feed_open: false,
          feed_tab: :feed,
          filter_query: "",
          selected_id: nil,
          selected_node: nil,
          project_root: project_root
        )}

      {:error, _reason} ->
        {:ok, assign(socket,
          context_json: nil,
          nodes_by_domain: %{},
          all_nodes: [],
          gap_count: 0,
          migration_count: 0,
          project_name: Path.basename(project_root),
          sidebar_tab: :system_map,
          lens: :default,
          system_map_view: :graph,
          drawer_open: false,
          drawer_tab: :details,
          feed_open: false,
          feed_tab: :feed,
          filter_query: "",
          selected_id: nil,
          selected_node: nil,
          project_root: project_root
        )}
    end
  end

  @impl true
  def handle_event("node_selected", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("set_sidebar_tab", %{"tab" => t}, socket) do
    {:noreply, assign(socket, sidebar_tab: String.to_existing_atom(t))}
  end

  @impl true
  def handle_event("set_lens", %{"lens" => l}, socket) do
    {:noreply, assign(socket, lens: String.to_existing_atom(l))}
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
    {:noreply, assign(socket, feed_tab: String.to_existing_atom(t))}
  end

  @impl true
  def handle_event("set_drawer_tab", %{"tab" => t}, socket) do
    {:noreply, assign(socket, drawer_tab: String.to_existing_atom(t))}
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
    case Foundry.Context.ProjectContext.build_one(project_root, module_id) do
      {:ok, node} ->
        {:noreply, push_event(socket, "node_detail", %{node: node})}
      {:error, _} ->
        {:noreply, socket}
    end
  end

  def abbr_type(nil), do: "unk"
  def abbr_type(type) do
    case type do
      "resource"     -> "res"
      "transfer"     -> "trx"
      "reactor"      -> "rct"
      "rule"         -> "rul"
      "job"          -> "job"
      "liveview"     -> "lv"
      "liveresource" -> "lr"
      "blueprint"    -> "bp"
      "provider"     -> "pv"
      "trigger"      -> "tg"
      "terminal"     -> "tm"
      _ -> type |> String.slice(0..2) |> String.upcase()
    end
  end

  def pip_status(node) do
    compliance = node["compliance"] || []
    tc = node["test_coverage"] || %{}
    has_gap = is_list(compliance) and Enum.any?(compliance) and not Map.get(tc, "e2e_tests", false)
    cond do
      has_gap           -> "fm-pip-gap"
      node["sensitive"] -> "fm-pip-sensitive"
      true              -> ""
    end
  end
end
