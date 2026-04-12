defmodule Foundry.LintRules.AshAiStepRule do
  @moduledoc """
  Agent steps must declare confidence thresholds, tools, and telemetry (INV-014..017).

  Rule IDs:
  - `:agent_step_missing_confidence_threshold` — decision/scorer step without confidence_threshold
  - `:agent_step_missing_tools` — agent step without explicit tools declaration
  - `:agent_step_missing_telemetry` — agent step without telemetry prefix

  These rules check Reactor modules that contain `:agent` steps. The step
  metadata is extracted from the Reactor DSL and validated against the
  invariants.
  """

  @behaviour SparkLint.Rule

  def check(module, ctx) do
    sensitive = ctx.metadata[:sensitive_modules] || []
    is_sensitive = module in sensitive

    violations =
      module
      |> extract_agent_steps()
      |> Enum.flat_map(fn step ->
        validate_agent_step(step, is_sensitive)
      end)

    {:ok, violations}
  rescue
    _ -> {:ok, []}
  end

  defp extract_agent_steps(module) do
    # Check if this is a Reactor module by looking for the Reactor DSL
    if reactor_module?(module) do
      case get_reactor_steps(module) do
        steps when is_list(steps) ->
          Enum.filter(steps, fn step ->
            step.step_kind == :agent
          end)

        _ ->
          []
      end
    else
      []
    end
  rescue
    _ -> []
  end

  defp reactor_module?(module) do
    :ok == Ash.Resource.Info.resource?(module) ||
      function_exported?(module, :reactor, 0)
  rescue
    _ -> false
  end

  defp get_reactor_steps(module) do
    # Try to extract steps from the Reactor DSL
    if function_exported?(module, :steps, 0) do
      module.steps()
    else
      []
    end
  rescue
    _ -> []
  end

  defp validate_agent_step(step, _is_sensitive) do
    violations = []

    # INV-014: decision/scorer steps must have confidence_threshold
    violations =
      if is_decision_or_scorer?(step) and is_nil(step.confidence_threshold) do
        [
          %SparkLint.Violation{
            rule: :agent_step_missing_confidence_threshold,
            module: step.__module__,
            message:
              "Agent step #{inspect(step.name)} in #{inspect(step.__module__)} is a #{step_type_label(step)} but does not declare a confidence_threshold. Add `confidence_threshold: 0.8` (or appropriate value) to the step.",
            severity: :error
          }
          | violations
        ]
      else
        violations
      end

    # INV-016: agent steps must declare tool access explicitly
    violations =
      if empty_step_tools?(step) do
        [
          %SparkLint.Violation{
            rule: :agent_step_missing_tools,
            module: step.__module__,
            message:
              "Agent step #{inspect(step.name)} in #{inspect(step.__module__)} does not declare tools. Add `tools: [:action_name, ...]` to the step definition.",
            severity: :error
          }
          | violations
        ]
      else
        violations
      end

    # INV-017: agent steps must emit telemetry
    violations =
      if empty_telemetry_prefix?(step) do
        [
          %SparkLint.Violation{
            rule: :agent_step_missing_telemetry,
            module: step.__module__,
            message:
              "Agent step #{inspect(step.name)} in #{inspect(step.__module__)} does not declare telemetry_prefix. Add `telemetry_prefix: [:app, :domain, :reactor, :step]`.",
            severity: :error
          }
          | violations
        ]
      else
        violations
      end

    violations
  end

  defp is_decision_or_scorer?(step) do
    step.type in [:decision, :scorer, "decision", "scorer"]
  end

  defp step_type_label(step) do
    case step.type do
      :decision -> "decision"
      "decision" -> "decision"
      :scorer -> "scorer"
      "scorer" -> "scorer"
      other -> inspect(other)
    end
  end

  defp empty_step_tools?(step) do
    is_nil(step.step_tools) or step.step_tools == []
  end

  defp empty_telemetry_prefix?(step) do
    is_nil(step.step_telemetry_prefix) or step.step_telemetry_prefix == []
  end
end
