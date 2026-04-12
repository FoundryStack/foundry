defmodule Foundry.Project.Status do
  @moduledoc """
  Ash resource wrapping the output of `mix foundry.project.status`.

  Represents the health summary of a target project: lint state, migration
  status, open proposals, compliance gaps, and stack versions.

  Delegates to `Foundry.Status.build/1` for the actual data.
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
      description("Project type from the manifest (e.g. 'standard', 'umbrella').")
      allow_nil?(false)
    end

    attribute :domain_type, :string do
      description("Domain type declared in the manifest.")
      allow_nil?(false)
    end

    attribute :domains, {:array, :string} do
      description("List of domain names discovered in the project.")
      default([])
    end

    attribute :sensitive_modules, {:array, :string} do
      description("Modules marked as sensitive in the manifest.")
      default([])
    end

    attribute :lint_errors, :integer do
      description("Count of lint errors.")
      default(0)
    end

    attribute :lint_warnings, :integer do
      description("Count of lint warnings.")
      default(0)
    end

    attribute :pending_migrations, :integer do
      description("Count of pending migrations.")
      default(0)
    end

    attribute :open_proposals, :integer do
      description("Count of open proposals.")
      default(0)
    end

    attribute :compliance_total, :integer do
      description("Total number of compliance requirements.")
      default(0)
    end

    attribute :compliance_covered, :integer do
      description("Number of compliance requirements with test coverage.")
      default(0)
    end

    attribute :stack_versions, :map do
      description("Map of dependency name to version string from mix.lock.")
      default(%{})
    end

    attribute :compiled_at, :utc_datetime do
      description("Timestamp of the most recent .beam file compilation.")
      allow_nil?(true)
    end

    attribute :generated_at, :utc_datetime do
      description("When this status snapshot was generated.")
      allow_nil?(false)
    end
  end

  actions do
    defaults [:read]
  end
end
