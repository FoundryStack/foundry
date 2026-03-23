defmodule Foundry.LintRules.DescriptionRule do
  @behaviour Foundry.SparkLint.Rule

  def check(module, _ctx) do
    violations = []

    # Reload module to get fresh docs from recompiled BEAM (important for mutation tests)
    # This ensures we catch mutations that remove @moduledoc
    try do
      # Try to reload the module from disk
      case :code.load_file(module) do
        {:module, _} -> :ok
        _ -> :ok
      end
    rescue
      _ -> :ok
    end

    # Check @moduledoc
    violations =
      case Code.fetch_docs(module) do
        {:docs_v1, _, _, _, :none, _, _} ->
          [%Foundry.SparkLint.Violation{
            rule:     :missing_description,
            module:   module,
            message:  "#{inspect module} is missing @moduledoc",
            severity: :error
          } | violations]

        {:docs_v1, _, _, _, :hidden, _, _} ->
          # @moduledoc false is acceptable
          violations

        _ ->
          violations
      end

    # Check Ash resource attribute descriptions
    violations =
      try do
        info = Foundry.SparkMeta.walk(module)

        Enum.reduce(info.attributes, violations, fn attr, acc ->
          if is_nil(attr.description) or attr.description == "" do
            [%Foundry.SparkLint.Violation{
              rule:     :missing_description,
              module:   module,
              message:  "#{inspect module}.#{attr.name} is missing a description:",
              severity: :error
            } | acc]
          else
            acc
          end
        end)
      rescue
        _ -> violations
      end

    {:ok, violations}
  end
end
