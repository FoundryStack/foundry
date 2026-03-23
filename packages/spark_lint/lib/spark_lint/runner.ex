defmodule SparkLint.Runner do
  @moduledoc """
  Executes a list of rules against a list of modules.

  Returns `{violations, errors}` where:
    - `violations` is a sorted list of `SparkLint.Violation` structs
      (sorted: :error first, then :warning, then :info; within severity by module name)
    - `errors` is a list of `%{rule: rule_module, module: module, reason: term}`
      for rules that returned `{:error, reason}`
  """

  def run(rules, modules, base_context \\ %{}) do
    # KNOWN LIMITATION: Uses `acc_v ++ new_v` which is O(n) per append. For ~30 modules × 7 rules,
    # this is acceptable (O(210²) ≈ 44K operations). Before `spark_lint` Hex extraction,
    # optimize to `[new_v | acc_v]` + `Enum.reverse/1` or accumulate as flat list with
    # `Enum.flat_map/2`. Phase 1 baseline is correct, just not optimal at scale.
    {violations, errors} =
      for rule <- rules, module <- modules, reduce: {[], []} do
        {acc_v, acc_e} ->
          ctx = %SparkLint.Context{
            module: module,
            modules: modules,
            metadata: Map.get(base_context, :metadata, %{})
          }

          case rule.check(module, ctx) do
            {:ok, new_v} -> {acc_v ++ new_v, acc_e}
            {:error, reason} -> {acc_v, acc_e ++ [%{rule: rule, module: module, reason: reason}]}
          end
      end

    sorted =
      Enum.sort_by(violations, fn v ->
        {case(v.severity, do: (:error -> 0; :warning -> 1; :info -> 2)), inspect(v.module)}
      end)

    {sorted, errors}
  end
end
