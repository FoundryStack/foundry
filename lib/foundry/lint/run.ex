defmodule Foundry.Lint.Run do
  @moduledoc """
  Ash resource wrapping the output of `mix foundry.lint.all`.

  Represents a single lint execution: the pass/fail result, violation counts,
  and the full list of violations across all lint rules and modules.

  Delegates to `Foundry.Lint.Runner.run/1` for the actual lint execution.
  """

  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Simple

  attributes do
    uuid_primary_key :id

    attribute :passed, :boolean do
      description("Whether the lint run passed (zero error-level violations).")
      allow_nil?(false)
    end

    attribute :error_count, :integer do
      description("Number of error-level violations.")
      default(0)
    end

    attribute :warning_count, :integer do
      description("Number of warning-level violations.")
      default(0)
    end

    attribute :info_count, :integer do
      description("Number of info-level violations.")
      default(0)
    end

    attribute :total_violations, :integer do
      description("Total number of violations across all severities.")
      default(0)
    end

    attribute :violations, {:array, :map} do
      description("List of individual lint violations with rule_id, severity, message, and module.")
      default([])
    end

    attribute :generated_at, :utc_datetime do
      description("When this lint run completed.")
      allow_nil?(false)
    end
  end

  actions do
    defaults [:read]
  end
end
