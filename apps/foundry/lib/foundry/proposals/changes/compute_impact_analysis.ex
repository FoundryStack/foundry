defmodule Foundry.Proposals.Changes.ComputeImpactAnalysis do
  @moduledoc """
  Runs ImpactAnalyzer during the submit action and stores the result in impact_analysis.
  Changed modules are derived from the operation_params[:module_contexts] when available,
  falling back to the proposal's operation field as a single module.
  Failures are non-fatal — impact_analysis remains nil rather than blocking submission.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    project_root = Application.get_env(:foundry, :current_project_root, File.cwd!())
    changed_modules = extract_changed_modules(changeset)

    case Foundry.Copilot.ImpactAnalyzer.compute(project_root, changed_modules) do
      {:ok, analysis} ->
        Ash.Changeset.force_change_attribute(changeset, :impact_analysis, analysis)

      {:error, _reason} ->
        changeset
    end
  end

  defp extract_changed_modules(changeset) do
    params = changeset.data.operation_params || %{}

    modules =
      case Map.get(params, "module_contexts") || Map.get(params, :module_contexts) do
        list when is_list(list) ->
          Enum.map(list, fn ctx ->
            Map.get(ctx, "id") || Map.get(ctx, :id)
          end)
          |> Enum.reject(&is_nil/1)

        _ ->
          []
      end

    if modules == [] do
      operation = changeset.data.operation
      if is_binary(operation) and operation != "", do: [operation], else: []
    else
      modules
    end
  end
end
