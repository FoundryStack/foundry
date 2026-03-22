defmodule Foundry.Lint.Runner do
  @moduledoc """
  High-level orchestrator for the lint suite.

  Composes manifest validation, module discovery, and per-module rule execution
  into a single `LintReport` struct suitable for CI/CLI output and JSON serialization.

  ## Usage

      report = Foundry.Lint.Runner.run(project_root)
      # => %Foundry.Lint.LintReport{
      #      passed: true,
      #      violations: [...],
      #      error_count: 0,
      #      warning_count: 2,
      #      info_count: 0,
      #      generated_at: "2026-03-22T..."
      #    }
  """

  alias Foundry.Lint.LintReport
  alias Foundry.LintRules.Registry

  def run(project_root) do
    {:ok, manifest} = Foundry.Manifest.Parser.read(project_root)

    # Manifest-level validation (e.g., missing approvers, invalid resources)
    manifest_violations = Foundry.LintRules.ManifestValidator.check(manifest)

    # Module-level discovery and validation
    project_name = Keyword.get(manifest, :project_name, "")
    modules = Foundry.Context.ModuleDiscovery.all_project_modules(project_root, project_name)

    metadata = %{
      manifest: manifest,
      sensitive_modules: Keyword.get(manifest, :sensitive_resources, []),
      project_root: project_root
    }

    {spark_violations, _rule_errors} =
      Foundry.SparkLint.Runner.run(
        Registry.module_rules(),
        modules,
        %{metadata: metadata}
      )

    # Merge manifest and module-level violations
    all_spark = manifest_violations ++ spark_violations

    # Convert SparkLint.Violation → LintReport.Violation (name field mapping: :rule → :rule_id)
    violations =
      all_spark
      |> Enum.map(&to_lint_violation/1)
      |> Enum.sort_by(fn v -> {severity_order(v.severity), v.module} end)

    error_count = Enum.count(violations, & &1.severity == :error)
    warning_count = Enum.count(violations, & &1.severity == :warning)
    info_count = Enum.count(violations, & &1.severity == :info)

    %LintReport{
      passed: error_count == 0,
      violations: violations,
      error_count: error_count,
      warning_count: warning_count,
      info_count: info_count,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp to_lint_violation(%Foundry.SparkLint.Violation{} = v) do
    %LintReport.Violation{
      rule_id: v.rule,
      severity: v.severity,
      message: v.message,
      module: inspect(v.module)
    }
  end

  defp severity_order(:error), do: 0
  defp severity_order(:warning), do: 1
  defp severity_order(_), do: 2
end
