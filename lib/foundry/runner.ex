defmodule Foundry.Lint.Context do
  @moduledoc "Context passed to every lint rule."
  defstruct [:module, :manifest, :all_modules, :project_root]
end

defmodule Foundry.Lint.Runner do
  @moduledoc """
  Executes all registered lint rules against every Foundry-relevant module
  and aggregates results into a `Foundry.Lint.LintReport`.

  ## Rule registry

  Rules are registered by implementing the `Foundry.Lint.Rule` behaviour and
  listed in `@rules` below. Adding a rule: implement the behaviour, add the
  module to the list. No other wiring required.

  ## Context

  Each rule receives a `Foundry.Lint.Context` struct containing:
  - The module under inspection
  - The parsed manifest (for sensitive_resources, conditional_libraries, etc.)
  - The full list of all modules (for cross-module rules like sensitive checks)
  - The project root path

  ## Parallelism

  Rules run serially per module to keep error reporting deterministic.
  Modules are processed in parallel with `Task.async_stream/3`.
  """

  alias Foundry.Lint.{Context, LintReport, LintReport.Violation}

  @rules [
    Foundry.Lint.Rules.DescriptionRule,
    Foundry.Lint.Rules.PaperTrailRule,
    Foundry.Lint.Rules.ArchivalRule,
    Foundry.Lint.Rules.IdempotencyRule,
    Foundry.Lint.Rules.RunbookRule,
    Foundry.Lint.Rules.ManifestValidator,
    Foundry.Lint.Rules.AdminRouteRule,
    Foundry.Lint.Rules.MoneyTypeRule,
    Foundry.Lint.Rules.DecoratorRule
  ]

  @doc """
  Run all rules against all modules. Returns a populated `LintReport`.
  """
  @spec run(project_root :: String.t()) :: LintReport.t()
  def run(project_root \\ File.cwd!()) do
    manifest = load_manifest(project_root)

    all_mods =
      Foundry.Context.Introspector.build_all(project_root: project_root)
      |> Map.values()
      |> List.flatten()

    mod_list = Enum.map(all_mods, fn ctx -> Module.concat([ctx.module]) end)

    violations =
      mod_list
      |> Task.async_stream(
        fn mod ->
          ctx = %Context{
            module: mod,
            manifest: manifest,
            all_modules: mod_list,
            project_root: project_root
          }

          run_rules(ctx)
        end,
        max_concurrency: System.schedulers_online(),
        timeout: 30_000
      )
      |> Enum.flat_map(fn
        {:ok, viols} ->
          viols

        {:exit, reason} ->
          [
            %Violation{
              rule_id: :lint_runner_error,
              severity: :error,
              message: "Rule crashed: #{inspect(reason)}"
            }
          ]
      end)

    # Also run manifest-level rules (not per-module)
    manifest_violations = run_manifest_rules(manifest, project_root)

    all_violations = violations ++ manifest_violations

    errors = Enum.count(all_violations, &(&1.severity == :error))
    warnings = Enum.count(all_violations, &(&1.severity == :warning))
    infos = Enum.count(all_violations, &(&1.severity == :info))

    %LintReport{
      passed: errors == 0,
      violations: all_violations,
      error_count: errors,
      warning_count: warnings,
      info_count: infos,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp run_rules(ctx) do
    Enum.flat_map(@rules, fn rule ->
      try do
        rule.check(ctx)
      rescue
        e ->
          [
            %Violation{
              rule_id: :rule_execution_error,
              severity: :error,
              message: "#{inspect(rule)} crashed: #{Exception.message(e)}",
              module: to_string(ctx.module)
            }
          ]
      end
    end)
  end

  defp run_manifest_rules(manifest, _project_root) do
    Foundry.Lint.Rules.ManifestValidator.check_manifest(manifest)
  end

  defp load_manifest(project_root) do
    path = Path.join([project_root, ".foundry", "manifest.exs"])

    case File.read(path) do
      {:ok, content} ->
        {kw, _} = Code.eval_string(content)
        kw

      _ ->
        []
    end
  end
end
