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
        context_json = Jason.encode!(context)
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
          drawer_open: false,
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
          drawer_open: false,
          selected_node: nil,
          project_root: project_root
        )}
    end
  end

  @impl true
  def handle_event("node_selected", %{"id" => _id, "data" => node_data}, socket) do
    {:noreply, assign(socket, selected_node: node_data, drawer_open: true)}
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

  # Helpers for template
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
      "provider" -> "pv"
      "trigger" -> "tg"
      "terminal" -> "tm"
      _ -> String.slice(type, 0..2) |> String.upcase()
    end
  end

  def pip_class(node) do
    compliance = node["compliance"] || []
    tc = node["test_coverage"] || %{}
    sensitive = node["sensitive"] || false

    has_gap = is_list(compliance) and Enum.any?(compliance) and not Map.get(tc, "e2e_tests", false)

    cond do
      has_gap -> "w-2 h-2 rounded-full bg-warning"
      sensitive -> "w-2 h-2 rounded-full bg-error"
      true -> "w-2 h-2 rounded-full bg-success"
    end
  end
end
