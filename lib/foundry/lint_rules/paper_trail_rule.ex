defmodule Foundry.LintRules.PaperTrailRule do
  @behaviour SparkLint.Rule

  def check(module, ctx) do
    sensitive = ctx.metadata[:sensitive_modules] || []

    if module in sensitive and not paper_trail?(module) do
      {:ok, [%SparkLint.Violation{
        rule:     :missing_paper_trail,
        module:   module,
        message:  "#{inspect module} is sensitive but does not use AshPaperTrail.Resource",
        severity: :error
      }]}
    else
      {:ok, []}
    end
  end

  defp paper_trail?(module) do
    AshPaperTrail.Resource in Spark.extensions(module)
  rescue
    _ -> false
  end
end
