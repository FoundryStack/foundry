defmodule Foundry.LintRules.ObanTriggerRule do
  @moduledoc """
  INV-011 extension: Sensitive resources with Oban queues must have paper_trail.

  Rule ID: `:oban_trigger_on_sensitive_unaudited`

  If a resource is declared sensitive in the manifest and has Oban queues
  (background jobs) but does not use AshPaperTrail, it is an error.
  Background processing of sensitive data without audit history is a
  compliance gap.
  """

  @behaviour SparkLint.Rule

  def check(module, ctx) do
    sensitive = ctx.metadata[:sensitive_modules] || []

    if module in sensitive and has_oban_queue?(module) and not paper_trail?(module) do
      {:ok,
       [
         %SparkLint.Violation{
           rule: :oban_trigger_on_sensitive_unaudited,
           module: module,
           message:
             "#{inspect(module)} is sensitive and processes Oban jobs but does not use AshPaperTrail.Resource. Background processing of sensitive data requires audit history.",
           severity: :error
         }
       ]}
    else
      {:ok, []}
    end
  end

  defp has_oban_queue?(module) do
    case Ash.Resource.Info.actions(module) do
      actions when is_list(actions) ->
        Enum.any?(actions, fn action ->
          action.change_managers |> Enum.any?(fn cm ->
            cm.module |> to_string() |> String.contains?("Oban")
          end)
        end)

      _ ->
        false
    end
  rescue
    _ -> false
  end

  defp paper_trail?(module) do
    AshPaperTrail.Resource in Spark.extensions(module)
  rescue
    _ -> false
  end
end
