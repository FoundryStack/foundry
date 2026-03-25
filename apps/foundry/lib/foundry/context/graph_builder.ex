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
    edge_list = edge_list ++ derive_auth_edges(nodes, node_map)

    edge_list
  end

  # Reactor steps: data-driven derivation from step_kind and target_resource
  # Steps now carry step_kind (:read, :write, :map, :custom) and target_resource (FQN)
  defp derive_reactor_edges(nodes, _node_map) do
    nodes
    |> Enum.filter(&(&1.type == "reactor"))
    |> Enum.flat_map(fn reactor ->
      reactor.steps
      |> Enum.flat_map(fn step ->
        # Use StepEntry struct fields if available
        target_resource = Map.get(step, :target_resource) || Map.get(step, "target_resource")
        step_kind = Map.get(step, :step_kind) || Map.get(step, "step_kind")

        if target_resource do
          case step_kind do
            :write -> [EdgeEntry.new(reactor.module, target_resource, :writes)]
            "write" -> [EdgeEntry.new(reactor.module, target_resource, :writes)]
            :read -> [EdgeEntry.new(reactor.module, target_resource, :reads)]
            "read" -> [EdgeEntry.new(reactor.module, target_resource, :reads)]
            _ -> []
          end
        else
          []
        end
      end)
    end)
  end

  # Oban jobs: linking to Reactor via @performs attribute or domain heuristic
  defp derive_job_edges(nodes, node_map) do
    nodes
    |> Enum.filter(&(&1.type == "job"))
    |> Enum.flat_map(fn job ->
      # Phase 1: Look for a reactor in the same domain
      # Phase 2+: Use @performs attribute if available
      job_domain = job.domain
      reactor = find_reactor_in_domain(node_map, job_domain)
      if reactor, do: [EdgeEntry.new(job.module, reactor.module, :async)], else: []
    end)
  end

  # Helper: find a reactor in the same domain as the job
  defp find_reactor_in_domain(node_map, domain) do
    node_map
    |> Enum.find(fn {_module, node} ->
      node.type == "reactor" and node.domain == domain
    end)
    |> then(&if &1, do: elem(&1, 1), else: nil)
  end

  # Resource relationships: driven by relationship data from SparkMeta
  defp derive_resource_edges(nodes, _node_map) do
    nodes
    |> Enum.filter(&(&1.type == "resource"))
    |> Enum.flat_map(fn resource ->
      resource.relationships
      |> Enum.flat_map(fn rel ->
        rel_type = Map.get(rel, :type) || Map.get(rel, "type")
        related = Map.get(rel, :related_resource) || Map.get(rel, "related_resource")

        if related do
          case rel_type do
            :belongs_to ->
              [EdgeEntry.new(resource.module, related, :references)]
            "belongs_to" ->
              [EdgeEntry.new(resource.module, related, :references)]
            :has_many ->
              [EdgeEntry.new(resource.module, related, :referenced_by)]
            "has_many" ->
              [EdgeEntry.new(resource.module, related, :referenced_by)]
            :has_one ->
              [EdgeEntry.new(resource.module, related, :referenced_by)]
            "has_one" ->
              [EdgeEntry.new(resource.module, related, :referenced_by)]
            :many_to_many ->
              [
                EdgeEntry.new(resource.module, related, :references),
                EdgeEntry.new(resource.module, related, :referenced_by)
              ]
            "many_to_many" ->
              [
                EdgeEntry.new(resource.module, related, :references),
                EdgeEntry.new(resource.module, related, :referenced_by)
              ]
            _ ->
              []
          end
        else
          []
        end
      end)
    end)
  end

  # Authentication edges: User resource with auth_strategies → token resources
  defp derive_auth_edges(nodes, _node_map) do
    nodes
    |> Enum.filter(&(&1.authentication_subject == true))
    |> Enum.flat_map(fn user_node ->
      user_node.auth_strategies
      |> Enum.flat_map(fn strategy ->
        token_resource = Map.get(strategy, :token_resource) || Map.get(strategy, "token_resource")
        if token_resource do
          [EdgeEntry.new(user_node.module, token_resource, :authenticates)]
        else
          []
        end
      end)
    end)
  end
end
