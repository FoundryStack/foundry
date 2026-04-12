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
    defaults [:read]
  end
end
