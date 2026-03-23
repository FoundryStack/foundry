defmodule Foundry.LintRules.ArchivalRule do
  @behaviour SparkLint.Rule

  def check(module, ctx) do
    sensitive = ctx.metadata[:sensitive_modules] || []

    if module in sensitive and not archival?(module) do
      {:ok, [%SparkLint.Violation{
        rule:     :missing_archival,
        module:   module,
        message:  "#{inspect module} is sensitive but does not use AshArchival.Resource",
        severity: :error
      }]}
    else
      {:ok, []}
    end
  end

  defp archival?(module) do
    AshArchival.Resource in Spark.extensions(module)
  rescue
    _ -> false
  end
end
