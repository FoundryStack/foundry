defmodule Foundry.LintRules.IdempotencyRule do
  @behaviour Foundry.SparkLint.Rule

  @side_effect_steps [:create, :update, :destroy, :action, :run]

  def check(module, _ctx) do
    info = Foundry.SparkMeta.walk(module)

    cond do
      info.type not in [:transfer, :reactor] ->
        {:ok, []}

      not has_side_effects?(info.steps) ->
        {:ok, []}

      not has_idempotency_key?(module) ->
        {:ok, [%Foundry.SparkLint.Violation{
          rule:     :missing_idempotency,
          module:   module,
          message:  "#{inspect module} has side effects but declares no @idempotency_key",
          severity: :error
        }]}

      true ->
        {:ok, []}
    end
  rescue
    _ -> {:ok, []}
  end

  defp has_side_effects?(steps) do
    Enum.any?(steps, &(&1.type in @side_effect_steps))
  end

  defp has_idempotency_key?(module) do
    attrs = module.__info__(:attributes)
    !is_nil(attrs[:idempotency_key]) or !is_nil(attrs[:idempotency])
  rescue
    _ -> false
  end
end
