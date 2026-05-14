defmodule Foundry.SpecKit.Document do
  @moduledoc """
  Ash resource representing a spec-kit document (ADR, runbook, finding, regulation, or usage rule).

  Delegates to `Foundry.Context.SpecKitIndexBuilder.build/1` for enumeration
  and document metadata extraction.

  Each document has a path, title, type, summary, and extracted tags.
  """

  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Simple

  attributes do
    attribute :id, :string do
      description("Unique identifier derived from the document path.")
      primary_key?(true)
      allow_nil?(false)
    end

    attribute :path, :string do
      description(
        "Relative path from project root (e.g. 'docs/adrs/ADR-001-stack-selection.md')."
      )

      allow_nil?(false)
    end

    attribute :title, :string do
      description("Document title extracted from the filename or content.")
      allow_nil?(false)
    end

    attribute :type, :atom do
      description("Document type: :adr, :runbook, :finding, :regulation, :agents, :usage_rules.")
      allow_nil?(false)
    end

    attribute :summary, :string do
      description("First paragraph of the document, truncated to ~300 characters.")
      allow_nil?(true)
    end

    attribute :tags, {:array, :string} do
      description("Extracted keyword tags for search and filtering.")
      default([])
    end
  end

  actions do
    defaults([:read])

    read :read_agents_md do
      description("Read the AGENTS.md spec-kit document.")
    end

    read :read_adr_index do
      description("Read the ADR index JSON file.")
    end
  end
end
