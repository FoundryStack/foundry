defmodule Foundry.LintRules.LiveViewStateCoverageRule do
  @behaviour SparkLint.Rule

  @required_assigns ~w(@loading @error)
  @empty_collection_patterns ~w(Enum.empty? == [] length( == 0)

  def check(module, _ctx) do
    cond do
      not liveview_module?(module) -> {:ok, []}
      not has_render_function?(module) -> {:ok, []}
      true -> check_state_coverage(module)
    end
  end

  defp check_state_coverage(module) do
    source = module_source(module)

    missing =
      Enum.reject(@required_assigns, &assign_referenced?(source, &1)) ++
        if empty_collection_handled?(source), do: [], else: [:empty_collection]

    if missing == [] do
      {:ok, []}
    else
      labels = Enum.map(missing, &to_string/1) |> Enum.join(", ")

      {:ok,
       [
         %SparkLint.Violation{
           rule: :missing_liveview_state_coverage,
           module: module,
           message:
             "#{inspect(module)} render/1 missing state coverage: #{labels}. " <>
               "LiveView components must handle: empty, loading, error, partial, full states.",
           severity: :warning
         }
       ]}
    end
  end

  defp liveview_module?(module) do
    module
    |> module_behaviours()
    |> Enum.any?(&(&1 == Phoenix.LiveView or &1 == Phoenix.LiveComponent))
  rescue
    _ -> false
  end

  defp has_render_function?(module) do
    function_exported?(module, :render, 1)
  rescue
    _ -> false
  end

  defp module_source(module) do
    case module.module_info(:compile)[:source] do
      nil -> ""
      path -> File.read!(to_string(path))
    end
  rescue
    _ -> ""
  end

  defp assign_referenced?(source, assign) do
    String.contains?(source, assign)
  end

  defp empty_collection_handled?(source) do
    Enum.any?(@empty_collection_patterns, &String.contains?(source, &1))
  end

  defp module_behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  rescue
    _ -> []
  end
end
