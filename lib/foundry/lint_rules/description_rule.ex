defmodule Foundry.LintRules.DescriptionRule do
  @behaviour Foundry.SparkLint.Rule

  def check(module, _ctx) do
    violations = []

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
