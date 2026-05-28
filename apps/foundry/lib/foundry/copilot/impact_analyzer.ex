defmodule Foundry.Copilot.ImpactAnalyzer do
  @moduledoc """
  Computes deterministic blast-radius impact analysis for a proposal.
  No LLM involved — pure graph traversal over the project context graph.

  Given a set of directly-changed modules, performs reverse-edge BFS to find all
  transitive dependents, then cross-references the manifest for sensitive resources
  and compliance requirements.
  """

  @blast_radius_relations [:reads, :writes, :references, :calls_action, :referenced_by]

  @spec compute(project_root :: String.t(), changed_modules :: [String.t()]) ::
          {:ok, map()} | {:error, term()}
  def compute(project_root, changed_modules) when is_list(changed_modules) do
    with {:ok, ctx} <- Foundry.Context.ProjectContext.build(project_root),
         {:ok, manifest} <- Foundry.Manifest.Parser.read(project_root) do
      edges = ctx.edges
      nodes = ctx.nodes

      affected_modules = bfs_affected(changed_modules, edges)
      affected_set = MapSet.new(affected_modules)

      sensitive_resources =
        manifest
        |> Keyword.get(:sensitive_resources, [])
        |> Enum.map(&to_string/1)
        |> MapSet.new()

      touches_sensitive = not MapSet.disjoint?(affected_set, sensitive_resources)

      compliance_requirements =
        edges
        |> Enum.filter(&(MapSet.member?(affected_set, &1.from) or MapSet.member?(affected_set, &1.to)))
        |> Enum.flat_map(& &1.compliance_ids)
        |> Enum.uniq()

      affected_tests =
        nodes
        |> Enum.filter(&is_test_node?/1)
        |> Enum.filter(fn node ->
          Enum.any?(edges, fn e ->
            (e.from == node.module or e.to == node.module) and
              (MapSet.member?(affected_set, e.from) or MapSet.member?(affected_set, e.to))
          end)
        end)
        |> Enum.map(& &1.module)

      {:ok,
       %{
         affected_modules: affected_modules,
         affected_tests: affected_tests,
         touches_sensitive_resources: touches_sensitive,
         compliance_requirements_affected: compliance_requirements,
         computed_at: DateTime.utc_now()
       }}
    end
  end

  defp bfs_affected(seed_modules, edges) do
    reverse_adj = build_reverse_adjacency(edges)
    visited = MapSet.new(seed_modules)
    queue = :queue.from_list(seed_modules)
    do_bfs(queue, visited, reverse_adj)
  end

  defp build_reverse_adjacency(edges) do
    edges
    |> Enum.filter(&(&1.relation in @blast_radius_relations))
    |> Enum.reduce(%{}, fn edge, acc ->
      Map.update(acc, edge.to, [edge.from], &[edge.from | &1])
    end)
  end

  defp do_bfs(queue, visited, reverse_adj) do
    case :queue.out(queue) do
      {:empty, _} ->
        MapSet.to_list(visited)

      {{:value, node}, rest} ->
        upstream = Map.get(reverse_adj, node, [])

        {new_queue, new_visited} =
          Enum.reduce(upstream, {rest, visited}, fn upstream_node, {q, v} ->
            if MapSet.member?(v, upstream_node) do
              {q, v}
            else
              {:queue.in(upstream_node, q), MapSet.put(v, upstream_node)}
            end
          end)

        do_bfs(new_queue, new_visited, reverse_adj)
    end
  end

  defp is_test_node?(%{type: :test}), do: true
  defp is_test_node?(%{module: module}) when is_binary(module), do: String.ends_with?(module, "Test")
  defp is_test_node?(_), do: false
end
