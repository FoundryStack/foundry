defmodule Mix.Tasks.Foundry.Lint.All do
  @shortdoc "Run all Foundry lint rules against the current project (INV-001 through INV-013)"

  @moduledoc """
  Runs the full Foundry lint suite against all compiled modules and the project
  manifest. Emits a JSON report and exits non-zero if any `:error` severity
  violations are found.

  ## Usage

      mix foundry.lint.all
      mix foundry.lint.all --json
      mix foundry.lint.all --format=text      # human-readable summary

  ## Exit codes

  - `0` — no `:error` violations (warnings and info are non-blocking)
  - `1` — one or more `:error` violations found
  - `2` — lint runner itself failed (bug in a rule or runner crash)

  ## CI integration

  Add to your CI pipeline:

      - run: mix foundry.lint.all

  The lint report is emitted to stdout. CI systems can capture it for
  artefact upload. Violations are printed in a stable order (by file path,
  then rule ID) so diffs between CI runs are meaningful.

  ## Violations

  Violations are sorted: errors first, then warnings, then info.
  Within each severity, sorted by module name then rule_id.

  ## JSON output shape

  Matches `Foundry.Lint.LintReport`. The `passed` field is `true` iff
  `error_count == 0`.
  """

  use Mix.Task

  alias Foundry.Lint.Runner

  @impl Mix.Task
  def run(args) do
    app = Mix.Project.config()[:app]
    Application.put_env(app, :foundry_tasks_only, true)

    Mix.Task.run("app.start")

    format = parse_format(args)
    project_root = File.cwd!()

    report = Runner.run(project_root)

    sorted_report = %{
      report
      | violations:
          Enum.sort_by(report.violations, &{severity_order(&1.severity), &1.module, &1.rule_id})
    }

    case format do
      :json ->
        IO.puts(Jason.encode!(sorted_report, pretty: true))
        unless report.passed do
          exit({:shutdown, 1})
        end

      :text ->
        print_text_report(sorted_report)
        unless report.passed do
          Mix.shell().error(
            "\n#{report.error_count} error(s), #{report.warning_count} warning(s). Lint failed."
          )

          exit({:shutdown, 1})
        end

        if report.warning_count > 0 do
          Mix.shell().info("\n#{report.warning_count} warning(s). Lint passed with warnings.")
        else
          Mix.shell().info("\nLint passed. No violations.")
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp parse_format(args) do
    cond do
      "--format=text" in args -> :text
      "--text" in args -> :text
      true -> :json
    end
  end

  defp severity_order(:error), do: 0
  defp severity_order(:warning), do: 1
  defp severity_order(:info), do: 2

  defp print_text_report(report) do
    if report.violations == [] do
      Mix.shell().info("✓ No violations found.")
    else
      report.violations
      |> Enum.each(fn v ->
        icon =
          case v.severity do
            :error -> "✗"
            :warning -> "⚠"
            :info -> "ℹ"
          end

        location = [v.module, v.file_path] |> Enum.reject(&is_nil/1) |> Enum.join(" — ")
        Mix.shell().info("#{icon} [#{v.rule_id}] #{location}\n  #{v.message}\n")
      end)

      Mix.shell().info(
        "#{report.error_count} error(s)  #{report.warning_count} warning(s)  #{report.info_count} info(s)"
      )
    end
  end
end
