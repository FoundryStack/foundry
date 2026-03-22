defmodule Foundry.Context.GraphBuilder do
  @moduledoc """
  Assembles the complete project graph by collecting all nodes and deriving edges
  between them based on structural and behavioral relationships.

  Edge derivation rules:
  - Reactor `:create`/`:update` steps → resource: `writes` edge
  - Reactor `:read`/`:read_one` steps → resource: `reads` edge
  - Oban worker with `@performs` → Reactor: `async` edge
  - Resource `belongs_to` relationship: `references` edge
  - Resource `has_many`/`has_one` relationship: `referenced_by` edge
  """

  alias Foundry.Context.{ModuleDiscovery, NodeBuilder, PendingMigrations, EdgeEntry}
  alias Foundry.SparkMeta

  @spec build(String.t(), list()) :: {list(NodeEntry.t()), list(EdgeEntry.t())}
  def build(project_root, manifest) do
    root_name = Keyword.get(manifest, :project_name, "")
    {:ok, pending_set} = PendingMigrations.check(project_root)

    nodes =
      ModuleDiscovery.all_project_modules(project_root, root_name)
      |> Enum.map(fn mod ->
        info = SparkMeta.walk(mod)
        pending = PendingMigrations.pending?(mod, pending_set)
        NodeBuilder.build(info, manifest, pending)
      end)
      |> Enum.sort_by(& &1.id)

    edges =
      nodes
      |> derive_edges()
      |> Enum.sort_by(&{&1.from, &1.to})

    {nodes, edges}
  end

  # ---------------------------------------------------------------------------
  # Edge derivation
  # ---------------------------------------------------------------------------

  defp derive_edges(nodes) do
    edge_list = []

    # Build a map for quick lookup: module_fqn -> node
    node_map = Map.new(nodes, fn node -> {node.module, node} end)

    # Derive edges from all sources
    edge_list = edge_list ++ derive_reactor_edges(nodes, node_map)
    edge_list = edge_list ++ derive_job_edges(nodes, node_map)
    edge_list = edge_list ++ derive_resource_edges(nodes, node_map)

    edge_list
  end

  # Reactor steps: create/update/read steps pointing to resources
  defp derive_reactor_edges(nodes, _node_map) do
    nodes
    |> Enum.filter(&(&1.type == "reactor"))
    |> Enum.flat_map(fn reactor ->
      reactor.steps
      |> Enum.flat_map(fn step ->
        case {step["type"], step["target_module"]} do
          {"create", target} when is_binary(target) ->
            [EdgeEntry.new(reactor.module, target, :writes)]
          {"update", target} when is_binary(target) ->
            [EdgeEntry.new(reactor.module, target, :writes)]
          {"read", target} when is_binary(target) ->
            [EdgeEntry.new(reactor.module, target, :reads)]
          {"read_one", target} when is_binary(target) ->
            [EdgeEntry.new(reactor.module, target, :reads)]
          _ -> []
        end
      end)
    end)
  end

  # Oban jobs: @performs attribute linking to Reactor
  defp derive_job_edges(nodes, _node_map) do
    nodes
    |> Enum.filter(&(&1.type == "job"))
    |> Enum.flat_map(fn job ->
      # The SparkMeta walker should provide @performs in the metadata
      case job do
        %{attributes: attrs} when is_list(attrs) ->
          attrs
          |> Enum.filter(&(Map.get(&1, "name") == "performs"))
          |> Enum.map(&Map.get(&1, "value"))
          |> Enum.filter(&is_binary/1)
          |> Enum.map(&EdgeEntry.new(job.module, &1, :async))
        _ -> []
      end
    end)
  end

  # Resource relationships: belongs_to/has_many/has_one
  defp derive_resource_edges(nodes, _node_map) do
    nodes
    |> Enum.filter(&(&1.type == "resource"))
    |> Enum.flat_map(fn resource ->
      resource.attributes
      |> Enum.flat_map(fn attr ->
        case {Map.get(attr, "relationship_type"), Map.get(attr, "related_resource")} do
          {"belongs_to", related} when is_binary(related) ->
            [EdgeEntry.new(resource.module, related, :references)]
          {"has_many", related} when is_binary(related) ->
            [EdgeEntry.new(resource.module, related, :referenced_by)]
          {"has_one", related} when is_binary(related) ->
            [EdgeEntry.new(resource.module, related, :referenced_by)]
          _ -> []
        end
      end)
    end)
  end
end
