defmodule Foundry.Context.ProjectMap do
  @moduledoc """
  Assembles and compacts the complete project context map.
  """

  @doc """
  Builds the complete project context map and applies structural compaction.
  """
  def build_all(project_root) do
    {:ok, context} = Foundry.Context.ProjectContext.build_map(project_root)
    Foundry.Context.Compact.compact(context)
  end

  def assemble(manifest, nodes, edges, spec_kit) do
    %{
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      project: Keyword.get(manifest, :project_name, ""),
      project_type: Keyword.get(manifest, :project_type, "standard"),
      nodes: nodes,
      edges: edges,
      spec_kit: spec_kit
    }
    |> maybe_add_domain_type(manifest)
    |> Foundry.Context.Compact.compact()
  end

  defp maybe_add_domain_type(m, manifest) do
    case Keyword.get(manifest, :domain_type, "") do
      "" -> m
      dt -> Map.put(m, :domain_type, dt)
    end
  end
end
