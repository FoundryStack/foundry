defmodule Foundry.LintRules.ManifestValidator do
  @moduledoc """
  Validates the manifest keyword list directly (not per-module).
  Does not implement SparkLint.Rule — it is run as a separate pass.
  """

  @spec check(manifest :: keyword()) :: [SparkLint.Violation.t()]
  def check(manifest) do
    []
    |> check_required_approvers(manifest)
    |> check_unknown_sensitive_resources(manifest)
    |> check_coverage_weights(manifest)
    |> check_exclusion_comments(manifest)
    |> check_cldr_backend(manifest)
  end

  defp check_required_approvers(acc, manifest) do
    approvers = Keyword.get(manifest, :approvers, [])

    Enum.reduce([:sensitive_lead, :compliance_officer], acc, fn key, a ->
      if Keyword.get(approvers, key) do
        a
      else
        [%SparkLint.Violation{
          rule:     :manifest_missing_required_approver,
          module:   Foundry.Manifest,
          message:  "manifest.approvers.#{key} is required but absent",
          severity: :error
        } | a]
      end
    end)
  end

  defp check_unknown_sensitive_resources(acc, manifest) do
    sensitive = Keyword.get(manifest, :sensitive_resources, [])
    exemptions = Keyword.get(manifest, :sensitive_resource_exemptions, [])

    Enum.reduce(exemptions, acc, fn exempt_mod, a ->
      unless exempt_mod in sensitive do
        [%SparkLint.Violation{
          rule:     :manifest_unknown_sensitive_resource,
          module:   Foundry.Manifest,
          message:  "#{inspect exempt_mod} is in sensitive_resource_exemptions but not in sensitive_resources",
          severity: :error
        } | a]
      else
        a
      end
    end)
  end

  defp check_coverage_weights(acc, manifest) do
    weights = Keyword.get(manifest, :coverage_weights, [])

    if weights == [] do
      acc
    else
      total = Keyword.values(weights) |> Enum.sum()

      if abs(total - 1.0) > 0.001 do
        [%SparkLint.Violation{
          rule:     :manifest_invalid_coverage_weights,
          module:   Foundry.Manifest,
          message:  "coverage_weights sum to #{Float.round(total, 6)}, must be 1.0 ± 0.001",
          severity: :error
        } | acc]
      else
        acc
      end
    end
  end

  defp check_exclusion_comments(acc, _manifest) do
    # Requires reading raw manifest source — deferred
    acc
  end

  defp check_cldr_backend(acc, _manifest) do
    # Requires introspecting project for CLDR backend modules — deferred
    acc
  end
end
