defmodule ExTracer.FlowExpander do
  @moduledoc false

  alias ExTracer.FlowSummary

  def expand_step(step, lookup, adapters \\ []) do
    expanded =
      Enum.find_value(adapters, [], fn adapter ->
        case adapter.expand_step(step, lookup) do
          [] -> nil
          steps -> steps
        end
      end) || []

    [step | expanded]
  end

  def maybe_expand_automatic_runtime_steps(steps, lookup, adapters \\ []) do
    Enum.flat_map(steps, fn step ->
      if Map.get(step, :capture_origin) == "automatic" do
        expand_step(step, lookup, adapters)
      else
        [step]
      end
    end)
  end

  def maybe_assert_result_step(step) do
    if step.result do
      [
        FlowSummary.expanded_step(step, %{
          type: :reaction,
          kind: :assert_result,
          provenance: :branch,
          status: FlowSummary.normalized_status(step, :matched),
          label: "Assert #{humanize_result(step.result)}",
          details: step.result,
          source_snippet: step.result
        })
      ]
    else
      []
    end
  end

  defp humanize_result(nil), do: "result"
  defp humanize_result(result), do: String.replace(result, "_", " ")
end
