defmodule Foundry.Verifiers.ReactorWithSideEffectsRequiresIdempotency do
  @moduledoc """
  Spark compile-time verifier: any Reactor with side-effecting step types
  (:create, :update, :destroy, :action, :run) must define @idempotency_key.

  Mirrors SparkLint.Rules.IdempotencyRule but runs at compile time.
  """

  use Spark.Dsl.Verifier

  @side_effect_step_types [:create, :update, :destroy, :action, :run]

  @impl true
  def verify(dsl_state) do
    module = Spark.Dsl.Verifier.get_persisted(dsl_state, :module)

    steps =
      try do
        Spark.Dsl.Verifier.get_entities(dsl_state, [:steps])
      rescue
        _ -> []
      end

    has_side_effects = Enum.any?(steps, &(&1.type in @side_effect_step_types))
    has_idempotency_key = module_attribute_defined?(module, :idempotency_key)

    if has_side_effects and not has_idempotency_key do
      {:error,
       Spark.Error.DslError.exception(
         message:
           "#{inspect(module)} has side-effecting steps but does not define @idempotency_key. " <>
             "Add `@idempotency_key :your_field` to ensure safe retries (INV-013).",
         module: module
       )}
    else
      :ok
    end
  end

  defp module_attribute_defined?(module, attr) do
    module.__info__(:attributes)
    |> Keyword.has_key?(attr)
  rescue
    _ -> false
  end
end
