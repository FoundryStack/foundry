defmodule Foundry.Project.Graph do
  @moduledoc """
  Ash resource wrapping the full project context graph from `mix foundry.project.context`.

  Represents the complete system map: all nodes (modules) and edges (relationships,
  data flows, rule applications) for a target project.

  Delegates to `Foundry.Context.ProjectContext.build/1` for the actual data.
  """

  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Simple

  attributes do
    uuid_primary_key :id

    attribute :project, :string do
      description("Project name from the manifest.")
      allow_nil?(false)
    end

    attribute :project_type, :string do
      description("Project type from the manifest.")
      allow_nil?(false)
    end

    attribute :domain_type, :string do
      description("Domain type from the manifest.")
      allow_nil?(false)
    end

    attribute :nodes, {:array, :map} do
      description("List of node entries (modules) in the project graph.")
      default([])
    end

    attribute :edges, {:array, :map} do
      description("List of edge entries (relationships/dependencies) in the project graph.")
      default([])
    end

    attribute :spec_kit, :map do
      description("Spec-kit index metadata: ADRs, runbooks, regulations, usage rules.")
      default(%{})
    end

    attribute :generated_at, :utc_datetime do
      description("When this graph was generated.")
      allow_nil?(false)
    end
  end

  actions do
    read :read do
      primary? true
      prepare fn query, _ ->
        project_root = query.context[:project_root] || File.cwd!()

        with {:ok, graph_map} <- build_graph(project_root) do
          record = Map.merge(%{"id" => Ash.UUIDv7.generate()}, graph_map)
          Ash.Query.load_data(query, [record])
        else
          {:error, _} = error -> error
        end
      end
    end
  end

  defp build_graph(project_root) do
    {:ok, manifest} = Foundry.Manifest.Parser.read(project_root)
    {nodes, edges} = Foundry.Context.GraphBuilder.build(project_root, manifest)

    project_name = Keyword.get(manifest, :project_name, "")
    project_type = Keyword.get(manifest, :project_type, "standard")
    domain_type = Keyword.get(manifest, :domain_type, "")
    domain_type_str = if is_atom(domain_type), do: Atom.to_string(domain_type), else: domain_type

    spec_kit = Foundry.Context.SpecKitIndexBuilder.build(project_root)

    {:ok, %{
      "project" => project_name,
      "project_type" => project_type,
      "domain_type" => domain_type_str,
      "nodes" => nodes,
      "edges" => edges,
      "spec_kit" => spec_kit || %{},
      "generated_at" => DateTime.utc_now()
    }}
  catch
    _ -> {:error, :build_failed}
  end
end
