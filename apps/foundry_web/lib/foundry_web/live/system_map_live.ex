defmodule FoundryWeb.SystemMapLive do
  use FoundryWeb, :live_view
  alias FoundryWeb.ChatSession

  @impl true
  def mount(_params, session, socket) do
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

    case Foundry.Context.ProjectContext.build(project_root) do
      {:ok, context} ->
        context_json = Jason.encode!(Foundry.Context.Compact.compact(context))
        nodes = context.nodes || []

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

        # Count gaps: compliance reqs + no E2E tests
        gap_count =
          Enum.count(nodes, fn n ->
            (n.compliance || []) |> Enum.any?(fn _ -> true end) and
              not n.test_coverage.e2e_tests
          end)

        # Count migrations
        migration_count = Enum.count(nodes, fn n -> n.pending_migrations end)

        {:ok, socket} =
          socket
          |> assign(
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
            gap_count: 0,
            migration_count: 0,
            project_name: Path.basename(project_root),
            sidebar_tab: :system_map,
            lens: :default,
            system_map_view: :graph,
            drawer_open: false,
            drawer_tab: :details,
            feed_open: false,
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
    {:noreply, assign_known(socket, :sidebar_tab, t, sidebar_tabs())}
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

    case Foundry.Context.ProjectContext.build_one(project_root, module_id) do
      {:ok, node} ->
        {:noreply, push_event(socket, "node_detail", %{node: node})}

      {:error, _} ->
        {:noreply, socket}
    end
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
      "provider" -> "pv"
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
        "provider" -> {"var(--color-secondary)", "#fff"}
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
end
