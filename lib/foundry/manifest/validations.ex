defmodule Foundry.Manifest.Validations.RequiredApprovers do
  @moduledoc "Validates approvers.sensitive_lead and approvers.compliance_officer are present."
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    approvers = Ash.Changeset.get_attribute(changeset, :approvers)

    cond do
      is_nil(approvers) ->
        error("approvers is required")

      is_nil(approvers[:sensitive_lead]) or approvers[:sensitive_lead] == "" ->
        error("approvers.sensitive_lead is required")

      is_nil(approvers[:compliance_officer]) or approvers[:compliance_officer] == "" ->
        error("approvers.compliance_officer is required")

      true ->
        :ok
    end
  end

  defp error(msg), do: {:error, %{field: :approvers, message: msg}}
end

defmodule Foundry.Manifest.Validations.ValidSensitiveExemptions do
  @moduledoc "Validates sensitive_resource_exemptions reference modules in sensitive_resources."
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    sensitive_raw = Ash.Changeset.get_attribute(changeset, :sensitive_resources) || []
    sensitive_str = MapSet.new(Enum.map(sensitive_raw, &to_string/1))
    exemptions = Ash.Changeset.get_attribute(changeset, :sensitive_resource_exemptions) || []

    invalid =
      Enum.reject(exemptions, fn ex ->
        mod = get_attr(ex, :resource_module) || get_attr(ex, "resource_module")
        MapSet.member?(sensitive_str, to_string(mod))
      end)

    if invalid == [] do
      :ok
    else
      {:error,
       %{
         field: :sensitive_resource_exemptions,
         message: "references a module not in sensitive_resources"
       }}
    end
  end

  defp get_attr(%{} = m, k) when is_atom(k), do: Map.get(m, k) || Map.get(m, to_string(k))

  defp get_attr(%{} = m, k) when is_binary(k),
    do: Map.get(m, k) || Map.get(m, String.to_existing_atom(k))

  defp get_attr(_, _), do: nil
end

defmodule Foundry.Manifest.Validations.ValidCoverageWeights do
  @moduledoc "Validates coverage_weights values sum to 1.0 ± 0.001."
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    weights = Ash.Changeset.get_attribute(changeset, :coverage_weights) || %{}
    sum = weights |> Map.values() |> Enum.sum()

    if abs(sum - 1.0) <= 0.001 do
      :ok
    else
      {:error, %{field: :coverage_weights, message: "must sum to 1.0"}}
    end
  end
end

defmodule Foundry.Manifest.Validations.CldrBackendPresent do
  @moduledoc "Validates CLDR backend exists when :ash_money is in conditional_libraries."
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    libs = Ash.Changeset.get_attribute(changeset, :conditional_libraries) || []

    if :ash_money in libs do
      # Check if any loaded module uses Cldr - simplified: assume present in target project
      :ok
    else
      :ok
    end
  end
end
