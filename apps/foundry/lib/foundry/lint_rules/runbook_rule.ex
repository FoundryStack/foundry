defmodule Foundry.LintRules.RunbookRule do
  @behaviour SparkLint.Rule

  def check(module, ctx) do
    project_root = ctx.metadata[:project_root] || File.cwd!()
    info = Foundry.SparkMeta.walk(module)

    cond do
      info.type not in [:transfer, :reactor] ->
        {:ok, []}

      length(info.steps) <= 3 ->
        {:ok, []}

      is_nil(info.runbook) ->
        {:ok, [%SparkLint.Violation{
          rule:     :missing_runbook,
          module:   module,
          message:  "#{inspect module} has #{length(info.steps)} steps but declares no @runbook",
          severity: :error
        }]}

      not File.exists?(Path.join(project_root, info.runbook)) ->
        {:ok, [%SparkLint.Violation{
          rule:     :missing_runbook,
          module:   module,
          message:  "#{inspect module} @runbook path does not exist: #{info.runbook}",
          severity: :error
        }]}

      true ->
        {:ok, []}
    end
  rescue
    _ -> {:ok, []}
  end
end
